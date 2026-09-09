# frozen_string_literal: true

# The per-record outcome file of an FPI run (fpi-connector risk D4).
#
# RunReport carries only counts. The connector needs each record's resulting
# state for its deletion ledger and for Bruce's report, so after an applied
# run every FPI plant the engine touched is written as one JSON line, and the
# totals as summary.json, under the run's output directory.
class FpiRunOutcomes
  def initialize(data_source:, run_id:, out_dir:)
    @data_source = data_source
    @run_id = run_id
    @out_dir = Pathname(out_dir)
  end

  def write(totals, manifest, started_at)
    @out_dir.mkpath
    write_records(started_at)
    write_summary(totals, manifest, started_at)
  end

  private

  def write_records(started_at)
    conflicts = SyncConflict.where(data_source: @data_source, sync_run_id: @run_id).index_by(&:syncable_id)
    scope = Plant.unscoped.where(data_source_id: @data_source.id).where(last_synced_at: started_at..)
    @out_dir.join('outcomes.jsonl').open('w') do |f|
      scope.select(:id, :source_record_id, :sync_state, :created_at, :deleted_at).find_each do |plant|
        f.puts JSON.generate(record(plant, conflicts[plant.id], started_at))
      end
    end
  end

  def record(plant, conflict, started_at)
    {
      source_record_id: plant.source_record_id, plant_id: plant.id, sync_state: plant.sync_state,
      created: plant.created_at >= started_at, deleted: plant.deleted_at.present?,
      conflict_id: conflict&.id, conflict_type: conflict&.conflict_type
    }
  end

  def write_summary(totals, manifest, started_at)
    summary = {
      run_id: @run_id, snapshot_id: manifest['snapshot_id'], environment: manifest['environment'],
      started_at: started_at.utc.iso8601, finished_at: Time.current.utc.iso8601,
      totals: totals.to_h.except(:invalid_details, :error_details),
      invalid_details: totals.invalid_details, error_details: totals.error_details
    }
    @out_dir.join('summary.json').write(JSON.pretty_generate(summary))
  end
end
