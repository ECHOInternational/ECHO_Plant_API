# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')

# Turns an fpi-connector payload shard into the row shape SourceSynchronizer#apply
# expects, and runs it (fpi-connector schema-delta item 1).
#
# A shard is {"attributes_version": 1, "plants": {"<PLANT_ID>": {...}}} where
# every row carries exactly the managed keys plus source_updated_at; the
# deletions file is {"attributes_version": 1, "deleted": {"<PLANT_ID>": {...}}}.
#
# The contract is stricter than EcPlantFeed's, because this feed recurs:
#   * a row missing a managed key, or carrying an extra one, is refused
#     (IncompleteRow) rather than filled with '' -- a silently filled key would
#     read as an upstream edit on every record;
#   * every managed key must have a reader on Plant, so a key that the deployed
#     model does not carry cannot be dropped silently;
#   * every value is a String after canonicalisation: scalars are stringified,
#     NUL bytes stripped (jsonb rejects them), and each relation set is passed
#     through its serializer's own parse/dump, so the canonical form is produced
#     by exactly one function on both sides of the comparison;
#   * family_id is '' or a lower-case UUID (ActiveRecord's uuid type nils a
#     malformed string silently);
#   * attributes_version must equal FpiDataSource::PLANT_ATTRIBUTES_VERSION.
#
# ONE LOCALE PER RUN (see EcPlantFeed): English. Deletions are never inferred
# from absence; only the connector's ledger states them, and then the engine
# raises a source_deletion conflict and changes nothing (decision 11).
class FpiPlantFeed
  class IncompleteRow < StandardError; end
  class VersionMismatch < StandardError; end

  # Lower-case only: \h would accept upper-case hex, which Postgres reads back lower-cased.
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  Result = Struct.new(:rows, :report, keyword_init: true)

  def initialize(data_source:, run_id: SecureRandom.hex(8))
    @data_source = data_source
    @run_id = run_id
  end

  # @param shard [Hash] a parsed shard file
  def build(shard)
    check_version!(shard)
    shard.fetch('plants').map { |uuid, attrs| row_for(uuid, attrs) }
  end

  # @param deletions [Hash] a parsed deletions.json
  def build_deletions(deletions)
    check_version!(deletions)
    deletions.fetch('deleted', {}).map do |uuid, meta|
      { source_record_id: uuid, deleted: true, attributes: {},
        source_updated_at: meta['source_updated_at'] || Time.current }
    end
  end

  # Applies one batch of rows through one synchronizer, in English.
  def run(rows, apply: true)
    return Result.new(rows: rows, report: nil) unless apply

    report = Mobility.with_locale(:en) do
      SourceSynchronizer.new(
        data_source: @data_source,
        model: Plant,
        source_attributes: FpiDataSource::PLANT_ATTRIBUTES,
        run_id: @run_id
      ).apply(rows)
    end
    Result.new(rows: rows, report: report)
  end

  # Every managed key must be readable on the deployed model; checked once per
  # run rather than per row. Raises on a key the model cannot answer.
  def self.ensure_readable!
    missing = FpiDataSource::PLANT_ATTRIBUTES.reject { |a| Plant.new.respond_to?(a) }
    raise IncompleteRow, "Plant has no reader for managed attributes: #{missing.join(', ')}" if missing.any?

    nil
  end

  private

  def check_version!(doc)
    version = doc['attributes_version']
    return if version == FpiDataSource::PLANT_ATTRIBUTES_VERSION

    raise VersionMismatch,
          "payload attributes_version #{version.inspect} but this API expects #{FpiDataSource::PLANT_ATTRIBUTES_VERSION}; rebaseline first"
  end

  def row_for(uuid, attrs)
    raise IncompleteRow, "#{uuid}: row is not an object" unless attrs.is_a?(Hash)

    fields = attrs.except('source_updated_at')
    check_keys!(uuid, fields)
    {
      source_record_id: uuid,
      deleted: false,
      attributes: FpiDataSource::PLANT_ATTRIBUTES.index_with { |a| canonical(uuid, a, fields[a]) },
      source_updated_at: attrs['source_updated_at'] || Time.current
    }
  end

  def check_keys!(uuid, fields)
    missing = FpiDataSource::PLANT_ATTRIBUTES - fields.keys
    extra = fields.keys - FpiDataSource::PLANT_ATTRIBUTES
    raise IncompleteRow, "#{uuid}: missing managed keys: #{missing.sort.join(', ')}" if missing.any?
    raise IncompleteRow, "#{uuid}: keys this data source does not govern: #{extra.sort.join(', ')}" if extra.any?
  end

  def canonical(uuid, attribute, value)
    serializer = FpiDataSource::RELATION_SETS[attribute]
    return serializer.dump(serializer.parse(value)) if serializer

    text = value.nil? ? '' : value.to_s.delete("\u0000")
    malformed_id = attribute == 'family_id' && !text.empty? && !UUID.match?(text)
    raise IncompleteRow, "#{uuid}: family_id is not a lower-case UUID: #{text.inspect}" if malformed_id

    text
  rescue ArgumentError, JSON::ParserError => e
    raise IncompleteRow, "#{uuid}: #{attribute}: #{e.message}"
  end
end
