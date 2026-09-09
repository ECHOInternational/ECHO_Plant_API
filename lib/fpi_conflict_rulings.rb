# frozen_string_literal: true

# Applies a reviewer's rulings file to open FPI conflicts in bulk
# (fpi-connector backlog A29, risk D5), on the plants:apply_review pattern:
#
#   {"decision": "D-060", "reviewer": "steve@echonet.org",
#    "rulings": [{"conflict_id": "<uuid>", "resolution": "KEEP_LOCAL"},
#                {"conflict_id": "<uuid>", "resolution": "ACCEPT_INCOMING"}]}
#
# Every payload names the decision-log entry that authorised it and the
# reviewer whose principal is stamped on each resolved conflict. The data
# change is SyncConflictResolution, shared with the resolveSyncConflict
# mutation. Dry run by default. Rulings for conflicts that are not open, not
# this data source's, or not found are refused and counted, never guessed.
class FpiConflictRulings
  RESOLUTIONS = %w[KEEP_LOCAL ACCEPT_INCOMING].freeze

  Result = Struct.new(:applied, :not_open, :missing, :refused, :failed, :errors, keyword_init: true)

  def initialize(data_source:, principal:, decision:, apply: false)
    @data_source = data_source
    @principal = principal
    @decision = decision
    @apply = apply
  end

  def apply(rulings)
    result = Result.new(applied: 0, not_open: 0, missing: 0, refused: 0, failed: 0, errors: [])
    rulings.each { |ruling| apply_ruling(ruling, result) }
    result
  end

  private

  def apply_ruling(ruling, result)
    conflict = open_conflict(ruling, result)
    return if conflict.nil?
    return refuse(ruling, result, "unknown resolution #{ruling['resolution'].inspect}") unless RESOLUTIONS.include?(ruling['resolution'])

    result.applied += 1
    resolve!(conflict, ruling['resolution']) if @apply
  rescue StandardError => e
    record_failure(ruling, result, e)
  end

  def record_failure(ruling, result, error)
    result.applied -= 1
    result.failed += 1
    result.errors << "#{ruling['conflict_id']}: #{error.class}: #{error.message}"
  end

  # The conflict a ruling names, when it belongs to this source and is open; counts the reasons it is not.
  def open_conflict(ruling, result)
    conflict = SyncConflict.find_by(id: ruling['conflict_id'], data_source_id: @data_source.id)
    if conflict.nil?
      result.missing += 1
    elsif conflict.status != 'open'
      result.not_open += 1
    else
      return conflict
    end
    nil
  end

  def resolve!(conflict, resolution)
    SyncConflict.transaction do
      SyncConflictResolution.new(conflict: conflict, principal_id: @principal.id).apply!(resolution)
    end
  end

  def refuse(ruling, result, reason)
    result.refused += 1
    result.errors << "#{ruling['conflict_id']}: #{reason}"
  end
end
