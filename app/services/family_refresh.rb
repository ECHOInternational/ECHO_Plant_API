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

  def initialize(upstream_rows)
    @upstream = upstream_rows
    @upstream_by_name = upstream_rows.index_by { |r| r[:name].downcase }
  end

  def diff
    local = Family.accepted.to_a
    added, col_id_conflicts = added_candidates(local).partition { |row| col_id_available?(row) }
    vanished = local.reject { |f| @upstream_by_name.key?(f.name.downcase) }

    build_diff(local, added, col_id_conflicts, vanished)
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

  def build_diff(local, added, col_id_conflicts, vanished)
    {
      added: added,
      col_id_conflicts: col_id_conflicts,
      vanished: vanished,
      affected_plant_counts: vanished.to_h { |f| [f.name, f.plants.count] },
      unchanged: local.size - vanished.size
    }
  end

  def added_candidates(local)
    local_names = local.to_set { |f| f.name.downcase }
    @upstream.reject { |r| local_names.include?(r[:name].downcase) }
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
