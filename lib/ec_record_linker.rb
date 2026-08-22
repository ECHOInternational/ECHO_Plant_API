# frozen_string_literal: true

# Links existing API plants to their ECHOcommunity originals, and seeds the
# merge base, so that SourceSynchronizer can be run at all.
#
# WHY THIS IS MANDATORY. SourceSynchronizer finds a record with
# `find_by(data_source_id:, source_record_id:)`. Every one of those columns is
# NULL today, so a first sync run would match nothing and take the create
# branch for every row — 830 duplicate plants. Nothing else in the codebase
# does this stamping.
#
# WHAT source_record_id IS. ECHOcommunity's Resource UUID *is* this
# application's plant id: the 2020 export preserved it, which is why the two
# datasets still join exactly five years later. So the identifier is the record's
# own id. That is unusual enough to be worth stating rather than leaving the
# reader to infer it from `source_record_id: plant.id`.
#
# THE MERGE BASE is the interesting part. With `source_snapshot` NULL,
# SourceSynchronizer treats base as unknown and — correctly, by its own
# reasoning — refuses to choose a side: anything not digest-identical becomes a
# conflict. Applied to this dataset that is thousands of conflicts, which is not
# review, it is noise.
#
# We have the genuine common ancestor: `db/seeds/Plants.json`, the 2020 export,
# checksummed in the migration workspace at baseline/SEED-BASELINE.md and
# verified to contain exactly the 322 ECHO-owned plants. Seeding it as the base
# makes the merge a real three-way:
#
#   local == base, incoming differs   -> apply ECHOcommunity's value (D-002)
#   local != base, incoming differs   -> genuine conflict, a human decides
#   local != base, incoming == base   -> keep the local edit
#
# So the only conflicts raised are records edited in plant-admin since 2020 that
# ECHOcommunity has also changed — which is exactly the set that deserves eyes.
#
# For plants imported by this migration rather than seeded in 2020, the base is
# current local state: they came from ECHOcommunity and have not diverged since,
# so base == local == incoming and the first run scores them synced.
class EcRecordLinker
  Result = Struct.new(:linked, :already_linked, :based_on_seed, :based_on_local,
                      :not_in_source, :failed, :errors, keyword_init: true)

  # @param source_uuids [Set<String>] ids ECHOcommunity actually holds. Only
  #   these are linked: stamping a plant that has no upstream original would
  #   invite a later feed to treat its absence as a deletion.
  # @param baseline [Hash<String, Hash>] uuid => 2020 attribute hash, already
  #   sliced to the managed attributes.
  def initialize(data_source:, source_uuids:, baseline:, apply: false)
    @data_source = data_source
    @source_uuids = source_uuids
    @baseline = baseline
    @apply = apply
  end

  # The 2020 export, sliced to the managed attributes and flattened to the
  # per-locale shape SourceSynchronizer compares. Mobility reads one locale at a
  # time, and the sync runs in :en, so the base is the English values.
  def self.baseline_from_seed(attributes, path = Rails.root.join('db/seeds/Plants.json'))
    return {} unless File.exist?(path)

    JSON.parse(File.read(path)).each_with_object({}) do |row, acc|
      english = (row['translations'] || {})['en'] || {}
      merged = row.merge(english)
      acc[row['uuid']] = attributes.index_with { |a| merged[a].to_s }
    end
  end

  def link
    result = Result.new(linked: 0, already_linked: 0, based_on_seed: 0,
                        based_on_local: 0, not_in_source: 0, failed: 0, errors: [])
    Plant.unscoped.find_each { |plant| link_one(plant, result) }
    result
  end

  private

  def link_one(plant, result)
    return result.not_in_source += 1 unless @source_uuids.include?(plant.id)
    return result.already_linked += 1 if plant.data_source_id.present?

    snapshot, origin = base_for(plant)
    count_link(result, origin)
    stamp(plant, snapshot) if @apply
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{plant.id}: #{e.class}: #{e.message}"
  end

  def count_link(result, origin)
    result.linked += 1
    origin == :seed ? result.based_on_seed += 1 : result.based_on_local += 1
  end

  # update_columns, not update!: this is provenance bookkeeping, not an
  # editorial change. It must not run validations, touch updated_at, or leave a
  # PaperTrail version implying someone edited the plant.
  def stamp(plant, snapshot)
    plant.update_columns(
      data_source_id: @data_source.id,
      source_record_id: plant.id,
      source_snapshot: snapshot,
      source_digest: SourceSynchronizer.canonical_digest(snapshot)
    )
  end

  # The 2020 export where we have it, otherwise current local state.
  def base_for(plant)
    seed = @baseline[plant.id]
    return [seed, :seed] if seed

    [SourceSynchronizer.local_attrs(plant, EcDataSource::PLANT_ATTRIBUTES), :local]
  end
end
