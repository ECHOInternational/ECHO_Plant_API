# frozen_string_literal: true

# The counts of one FPI run: the engine's RunReport totals summed over every
# shard, the rows built, and the prediction made before anything was written.
class FpiRunTotals
  COUNTS = %i[created applied synced locally_modified conflicts_created conflicts_updated
              source_deletion_conflicts tombstone_kept unknown_deleted invalid errored].freeze

  attr_accessor :shards, :rows, :prediction, :invalid_details, :error_details, *COUNTS

  def initialize
    @shards = 0
    @rows = 0
    @prediction = nil
    @invalid_details = []
    @error_details = []
    COUNTS.each { |k| instance_variable_set(:"@#{k}", 0) }
  end

  def [](key)
    public_send(key)
  end

  def merge!(report)
    return unless report

    COUNTS.each { |k| public_send(:"#{k}=", self[k] + report.public_send(k)) }
    invalid_details.concat(report.invalid_details)
    error_details.concat(report.error_details)
  end

  def failed?
    errored.positive? || invalid.positive?
  end

  def to_h
    { shards: shards, rows: rows, **COUNTS.index_with { |k| self[k] }, invalid_details: invalid_details, error_details: error_details }
  end
end
