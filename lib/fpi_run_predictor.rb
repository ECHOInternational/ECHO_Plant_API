# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')

# Predicts what SourceSynchronizer would do with a batch of rows, writing
# nothing (fpi-connector risks D5 and G1). The engine's dry run only builds
# rows; this reads each record's base, local and incoming state through the
# same class methods the engine uses and classifies the row the same way, so
# an operator sees the shape of a run before APPLY, and the run refuses to
# start when the predicted conflicts exceed the cap.
class FpiRunPredictor
  OUTCOMES = %i[create synced applied locally_modified conflict converge source_deletion tombstone_kept unknown_deleted].freeze
  # One side changed (or neither): [local changed, incoming changed] -> outcome.
  ONE_SIDE = { [false, false] => :synced, [false, true] => :applied, [true, false] => :locally_modified }.freeze

  Prediction = Struct.new(*OUTCOMES, :rows, keyword_init: true) do
    def self.empty
      new(rows: 0, **OUTCOMES.index_with { 0 })
    end

    def add(outcome)
      self[outcome] += 1
      self.rows += 1
    end
  end

  def initialize(data_source:, attributes: FpiDataSource::PLANT_ATTRIBUTES)
    @data_source = data_source
    @attributes = attributes.map(&:to_s)
  end

  def predict(rows)
    prediction = Prediction.empty
    Mobility.with_locale(:en) do
      rows.each { |row| prediction.add(classify(row)) }
    end
    prediction
  end

  def classify(row)
    record = Plant.find_by(data_source_id: @data_source.id, source_record_id: row[:source_record_id])
    return row[:deleted] ? :unknown_deleted : :create if record.nil?
    return :tombstone_kept if record.deleted_at.present?
    return :source_deletion if row[:deleted]

    compare(record, row[:attributes].stringify_keys.slice(*@attributes))
  end

  private

  def compare(record, incoming)
    local_digest = digest(SourceSynchronizer.local_attrs(record, @attributes))
    incoming_digest = digest(incoming)
    base = record.source_snapshot&.slice(*@attributes)
    same = local_digest == incoming_digest
    return same ? :synced : :conflict if base.nil? # first sync of a pre-existing record

    base_digest = digest(base)
    outcome(base_digest != local_digest, base_digest != incoming_digest, same)
  end

  # The engine's decision table (SourceSynchronizer#compare_and_sync), keyed
  # by [local changed, incoming changed]; both changed splits on sameness.
  def outcome(local_changed, incoming_changed, same)
    return same ? :converge : :conflict if local_changed && incoming_changed

    ONE_SIDE.fetch([local_changed, incoming_changed])
  end

  def digest(hash)
    SourceSynchronizer.canonical_digest(hash)
  end
end
