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
# #diff itself is delegated to FamilyRefresh::DiffBuilder (own file, mirroring
# FamilyRefresh::Report) so this class stays under Metrics/ClassLength.
class FamilyRefresh
  # Raised by #apply_additions! instead of letting a raw uniqueness
  # violation escape. See ColIdCollisionError below for why this exists.
  class ColIdCollisionError < StandardError; end

  # Columns #apply_additions! is allowed to touch when an "added" row's
  # upsert lands on an existing row rather than inserting a fresh one. This
  # differs from FamilySeeder::REFRESHABLE_ATTRIBUTES by including status and
  # superseded_by_id: a resurrection (see DiffBuilder#split_resurrected) must
  # flip status back to accepted and clear a now-dangling superseded_by_id,
  # which a plain re-seed must never do. In the ordinary case -- a genuinely
  # new name -- the row has no existing match at all, so this list never
  # comes into play; it exists as the second line of defense the class
  # comment on DiffBuilder#col_id_available? already establishes the pattern
  # for.
  ADDITION_UPDATE_ONLY = %i[col_id kingdom plant_type status superseded_by_id
                            classification_version snapshot_date].freeze

  # client defaults to a real CatalogueOfLife so the rake task does not have
  # to thread one through; specs always inject a stub/double here so the
  # per-name synonym lookups below never touch the network.
  def initialize(upstream_rows, client: CatalogueOfLife.new)
    @upstream = upstream_rows
    @upstream_by_name = upstream_rows.index_by { |r| r[:name].downcase }
    @client = client
  end

  def diff
    DiffBuilder.new(@upstream, @upstream_by_name, @client).call
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
  # itself. Deliberately just this one assignment; see
  # DiffBuilder#exclude_rename_targets for why renamed_candidates must never
  # be auto-applied as a merge, nor auto-inserted as an addition.
  def apply_rename(family, new_name)
    family.update!(name: new_name)
  end

  # Re-accepts a family Catalogue of Life resurrected after we had already
  # merged it away (see DiffBuilder#split_resurrected). Undoes exactly the
  # two fields #apply_merge set -- status and superseded_by -- refreshes the
  # taxonomic facts sourced from COL, and deliberately touches nothing else:
  # the plants that were repointed onto the absorbing family during the
  # merge stay there. COL re-accepting a name is not evidence about which
  # specific plants belong under it, so this never repoints anything,
  # matching the "never silently repoint a plant" rule the whole class is
  # built around.
  def apply_resurrection!(candidate, version: CatalogueOfLife::DEFAULT_VERSION,
                          snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT)
    row = candidate[:row]
    candidate[:family].update!(
      status: 'accepted',
      superseded_by_id: nil,
      col_id: row[:col_id],
      kingdom: row[:kingdom],
      plant_type: row[:plant_type],
      classification_version: version,
      snapshot_date: snapshot_date
    )
  end

  # Writes only the rows #diff already classified as :added -- names with no
  # local match at all (not a rename target, not a resurrected name) and a
  # col_id that collides with nothing else in the batch or the table. That
  # filtering is what makes this safe to run inside the one transaction
  # Family.importing opens. update_only: ADDITION_UPDATE_ONLY and the rescue
  # below are both second lines of defense for a caller that skips #diff and
  # hands this a conflicting row directly (see the col_id collision hazard
  # on DiffBuilder#col_id_available?, and ADDITION_UPDATE_ONLY's own comment).
  def apply_additions!(added, version: CatalogueOfLife::DEFAULT_VERSION,
                       snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT)
    return 0 if added.empty?

    now = Time.current
    attributes = added.map { |row| addition_attributes(row, version, snapshot_date, now) }
    Family.bulk_upsert(attributes, update_only: ADDITION_UPDATE_ONLY)
  rescue ActiveRecord::RecordNotUnique => e
    raise ColIdCollisionError,
          "a col_id collided with an existing family row (#{e.message}); " \
          're-run families:refresh to get a fresh report before trying again'
  end

  private

  # translations is deliberately omitted here, not set to {}: see
  # FamilySeeder#write! for the regression this avoids. An explicit
  # translations: {} collapses to a literal SQL NULL under upsert_all
  # because it equals the Mobility container coder's own "empty" value, and
  # families.translations is NOT NULL. Omitting the key lets the INSERT fall
  # through to the column's own DEFAULT '{}' instead.
  #
  # superseded_by_id: nil is explicit, matching ADDITION_UPDATE_ONLY, even
  # though DiffBuilder#split_resurrected already keeps a resurrected name
  # (the one case where an existing row could have a non-nil
  # superseded_by_id) out of +added+ entirely. Belt-and-suspenders: if that
  # filtering is ever bypassed, this is what stops the dangling pointer
  # rather than merely narrowing it.
  def addition_attributes(row, version, snapshot_date, now)
    row.merge(status: 'accepted', superseded_by_id: nil, classification_source: 'catalogue-of-life',
              classification_version: version, snapshot_date: snapshot_date,
              created_at: now, updated_at: now)
  end
end
