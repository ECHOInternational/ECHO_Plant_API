# frozen_string_literal: true

# Diffs the locked family list against a Catalogue of Life release.
#
# The governing rule is that a refresh NEVER silently repoints a plant. It
# reports what changed; a human confirms; only then is anything applied.
#
# Matching is by NAME, not by COL identifier. COL identifiers are forced to
# change whenever a name flips between accepted and synonym, which is exactly
# what a merge is, so keying on them would make merges undetectable and would
# orphan our rows. Family names are stable; their status is what moves.
#
# Extracted into app/services, mirroring FamilySeeder, FamilyReconciler and
# FamilySeedBankingLoader: the rake task stays a thin CLI wrapper and the
# part that actually touches the database gets an automated regression test.
class FamilyRefresh
  # Raised by #apply_additions! instead of letting a raw uniqueness
  # violation escape. See ColIdCollisionError below for why this exists.
  class ColIdCollisionError < StandardError; end

  # client defaults to a real CatalogueOfLife so the rake task does not have
  # to thread one through; specs always inject a stub/double here so the
  # per-name synonym lookups below never touch the network.
  def initialize(upstream_rows, client: CatalogueOfLife.new)
    @upstream = upstream_rows
    @upstream_by_name = upstream_rows.index_by { |r| r[:name].downcase }
    @client = client
  end

  def diff
    local = Family.accepted.to_a
    local_names = local.to_set { |f| f.name.downcase }
    added, col_id_conflicts, added_names = partition_upstream(local_names)
    vanished = local.reject { |f| @upstream_by_name.key?(f.name.downcase) }

    build_diff(local, added, col_id_conflicts, vanished, classify_vanished(vanished, added_names, local_names))
  end

  # A merge is applied only after a human has confirmed it. Plants move to
  # the accepted family and the old row is kept, marked superseded, so that
  # any reference to it still resolves and the history stays readable. Never
  # destroys the old row: plants.family_id's foreign key is NO ACTION, and
  # the nullify callback that protects it only runs on an ActiveRecord
  # destroy, not on a raw DELETE.
  def apply_merge(from_family, to_family)
    Family.transaction do
      from_family.plants.update_all(family_id: to_family.id)
      from_family.update!(status: 'superseded', superseded_by: to_family)
    end
  end

  # A rename is the one case where nothing about ownership moves: same
  # taxon, new label. The family keeps its own UUID, so every plant that
  # already referenced it keeps referencing this exact row -- no
  # repointing, no superseding, no PaperTrail noise beyond the name change
  # itself. Deliberately just this one assignment; see the class comment on
  # #diff for why renamed_candidates must never be auto-applied as a merge.
  def apply_rename(family, new_name)
    family.update!(name: new_name)
  end

  # Writes only the rows #diff already classified as :added -- names with no
  # local match and a col_id that collides with nothing else in the batch or
  # the table. That filtering is what makes this safe to run inside the one
  # transaction Family.importing opens; the rescue below is a second line of
  # defense for a caller that skips #diff and hands this a conflicting row
  # directly (see the col_id collision hazard in the class comment above).
  def apply_additions!(added, version: CatalogueOfLife::DEFAULT_VERSION,
                       snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT)
    return 0 if added.empty?

    now = Time.current
    Family.importing do
      added.each_slice(500) do |slice|
        Family.upsert_all(slice.map { |row| addition_attributes(row, version, snapshot_date, now) },
                          unique_by: 'index_families_on_lower_name')
      end
    end
    added.size
  rescue ActiveRecord::RecordNotUnique => e
    raise ColIdCollisionError,
          "a col_id collided with an existing family row (#{e.message}); " \
          're-run families:refresh to get a fresh report before trying again'
  end

  private

  def build_diff(local, added, col_id_conflicts, vanished, classification)
    {
      added: added,
      col_id_conflicts: col_id_conflicts,
      vanished: vanished,
      affected_plant_counts: vanished.to_h { |f| [f.name, f.plants.count] },
      unchanged: local.size - vanished.size
    }.merge(classification)
  end

  def partition_upstream(local_names)
    added, col_id_conflicts = added_candidates(local_names).partition { |row| col_id_available?(row) }
    [added, col_id_conflicts, added.to_set { |r| r[:name].downcase }]
  end

  def added_candidates(local_names)
    @upstream.reject { |r| local_names.include?(r[:name].downcase) }
  end

  # Splits the single "gone" bucket into the four cases the design doc
  # distinguishes (docs/superpowers/specs/2026-08-05-botanical-families-design.md
  # section 9), using one CatalogueOfLife#synonym_lookup request per vanished
  # name -- never per family, since a real COL monthly release moves the
  # family count by single digits. Detection only: nothing here writes
  # anything. A human reads the report and chooses #apply_rename or
  # #apply_merge; #diff never picks for them.
  #
  # Real split detection (design doc: "new accepted families appeared under
  # the SAME PARENT") would need each vanished name's higher classification
  # (its order) compared against every added row's, which neither our
  # schema nor CatalogueOfLife#all_families carries, and fetching it per
  # added row would violate the one-request-per-VANISHED-name budget this
  # method is built to respect. Absent that, a COL "ambiguous synonym" --
  # COL's own status for a name with no single successor -- is used as the
  # best available proxy for a split; see the class comment above
  # +classify_family+ and the fix report for the full reasoning.
  def classify_vanished(vanished, added_names, local_names)
    buckets = { renamed_candidates: [], merge_candidates: [], split_candidates: [], no_successor: [] }
    vanished.each do |family|
      key, entry = classify_family(family, added_names, local_names)
      buckets[key] << entry
    end
    buckets
  end

  # Never raises: a lookup failure or a status this method does not
  # recognize both fall through to :no_successor, reported and unapplied,
  # exactly like a genuine disappearance -- never guessed at, never
  # silently dropped.
  def classify_family(family, added_names, local_names)
    result = @client.synonym_lookup(family.name)
    case result[:status]
    when :synonym then classify_synonym(family, result[:accepted_name], added_names, local_names)
    when :ambiguous_synonym then [:split_candidates, candidate(family)]
    else [:no_successor, candidate(family)]
    end
  rescue StandardError
    [:no_successor, candidate(family)]
  end

  def classify_synonym(family, target_name, added_names, local_names)
    return [:no_successor, candidate(family)] if target_name.blank?
    return [:renamed_candidates, candidate(family, target_name)] if added_names.include?(target_name.downcase)
    return [:merge_candidates, candidate(family, target_name)] if local_names.include?(target_name.downcase)

    # The target is neither newly added nor already held under that exact
    # name -- most likely an authorship/formatting difference in the name
    # string COL returned. Report it, do not guess which bucket it belongs
    # in.
    [:no_successor, candidate(family, target_name)]
  end

  def candidate(family, target_name = nil)
    { family: family, plant_count: family.plants.count, target_name: target_name }
  end

  # Guards the col_id hazard carried over from the seeder: col_id has its
  # own unique partial index (index_families_on_col_id), separate from the
  # lower(name) index this diff matches on. A COL release can recycle an id
  # onto a different family than the one that held it locally, or two new
  # rows in the same release can arrive sharing one id; either would abort
  # the whole Family.importing transaction with a hard uniqueness violation
  # mid-batch. Filtering here, before any write is attempted, turns that
  # crash into a reviewable list (diff[:col_id_conflicts]) instead. Mutates
  # the memoized set so a duplicate col_id among the added rows themselves
  # is caught too, not just a collision with an existing row.
  def col_id_available?(row)
    return true if row[:col_id].blank?
    return false if seen_col_ids.include?(row[:col_id])

    seen_col_ids << row[:col_id]
    true
  end

  def seen_col_ids
    @seen_col_ids ||= Family.where.not(col_id: nil).pluck(:col_id).to_set
  end

  # translations is deliberately omitted here, not set to {}: see
  # FamilySeeder#write! for the regression this avoids. An explicit
  # translations: {} collapses to a literal SQL NULL under upsert_all
  # because it equals the Mobility container coder's own "empty" value, and
  # families.translations is NOT NULL. Omitting the key lets the INSERT fall
  # through to the column's own DEFAULT '{}' instead.
  def addition_attributes(row, version, snapshot_date, now)
    row.merge(status: 'accepted', classification_source: 'catalogue-of-life',
              classification_version: version, snapshot_date: snapshot_date,
              created_at: now, updated_at: now)
  end
end
