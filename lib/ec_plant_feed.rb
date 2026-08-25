# frozen_string_literal: true

require Rails.root.join('lib/ec_data_source')

# Turns an ECHOcommunity export into the row shape SourceSynchronizer#apply
# expects, and runs it.
#
# ONE LOCALE PER RUN. SourceSynchronizer reads local state through Mobility's
# public readers, so it compares whatever locale is current. `source_snapshot`
# is a single blob per record, not one per locale, so the substrate can only
# carry one language's baseline — and the baseline we have, the 2020 export, is
# English. This class therefore syncs English and nothing else.
#
# That is not a limitation we are working around; it matches where the work
# actually is. Measured on production: English has 88 values that differ on both
# sides — genuine conflicts, which is what a three-way merge is for. Spanish has
# almost none: 1,229 of its 1,732 values exist ONLY in ECHOcommunity, so there
# is nothing to conflict with. Spanish is an additive backfill, handled
# elsewhere, and forcing it through this machinery would invent conflicts
# against an English baseline that says nothing about it.
#
# EVERY ROW MUST CARRY EVERY ATTRIBUTE. The synchronizer slices both sides to
# EcDataSource::PLANT_ATTRIBUTES before digesting. A key missing from a row is
# not "unchanged" — it changes the digest and reads as an edit. So the builder
# fills absent text with '' rather than omitting the key, and a row that cannot
# supply the full set is rejected rather than sent.
#
# DELETIONS ARE NOT INFERRED. The synchronizer has no "absent from the feed
# means deleted" rule, deliberately. A plant missing from an export because the
# export failed halfway must never read as an upstream deletion. Deletions have
# to be stated explicitly, and this migration does not state any: ECHOcommunity
# deletions were handled once, under D-007, by the visibility alignment.
class EcPlantFeed
  class IncompleteRow < StandardError; end

  Result = Struct.new(:rows, :report, keyword_init: true)

  def initialize(data_source:, run_id: SecureRandom.hex(8))
    @data_source = data_source
    @run_id = run_id
  end

  # @param plants [Hash] uuid => { 'description' => '...', ... } as exported
  #   from ECHOcommunity, already mapped to API attribute names.
  def build(plants)
    plants.map { |uuid, attrs| row_for(uuid, attrs) }
  end

  # Builds and applies in one step, in English.
  def run(plants, apply: true)
    rows = build(plants)
    return Result.new(rows: rows, report: nil) unless apply

    report = Mobility.with_locale(:en) do
      SourceSynchronizer.new(
        data_source: @data_source,
        model: Plant,
        source_attributes: EcDataSource::PLANT_ATTRIBUTES,
        run_id: @run_id
      ).apply(rows)
    end
    Result.new(rows: rows, report: report)
  end

  private

  # source_updated_at rides alongside the attributes in the export but is row
  # metadata, not a managed attribute, so it is lifted out before the guard.
  def row_for(uuid, attrs)
    fields = attrs.except('source_updated_at')
    unmanaged = fields.keys - EcDataSource::PLANT_ATTRIBUTES
    if unmanaged.any?
      raise IncompleteRow,
            "#{uuid}: keys this data source does not govern: #{unmanaged.sort.join(', ')}"
    end

    {
      source_record_id: uuid,
      deleted: false,
      attributes: EcDataSource::PLANT_ATTRIBUTES.index_with { |a| fields[a].to_s },
      source_updated_at: attrs['source_updated_at'] || Time.current
    }
  end
end
