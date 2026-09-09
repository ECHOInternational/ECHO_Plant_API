# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')
require Rails.root.join('lib/fpi_plant_feed')
require Rails.root.join('lib/fpi_sync_run')
require Rails.root.join('lib/fpi_rebaseline')
require Rails.root.join('lib/fpi_conflict_rulings')
require Rails.root.join('lib/fpi_rollback')
require Rails.root.join('lib/fpi_payload_store')

# The Food Plants International import (fpi-connector plan, milestone M2).
#
#   bin/rails fpi:bootstrap                        # mirror the FPI organization, create the DataSource (idempotent)
#   bin/rails fpi:preflight[path/to/payload]        # everything a run needs, sends nothing
#   bin/rails fpi:sync_plants[path/to/payload]      # dry run: build every row, send nothing
#   APPLY=true RUN_ID=<id> bin/rails fpi:sync_plants[path/to/payload]
#   bin/rails fpi:rebaseline                        # dry run; APPLY=true to write, after bumping PLANT_ATTRIBUTES_VERSION
#
# One convention for the namespace: a payload argument (a directory, or
# s3://bucket/fpi/payloads/<run_id> as delivered by the connector, fetched
# into a temporary directory), dry run by default and APPLY=true to write,
# RUN_ID supplied by the connector (never random on a real run), non-zero
# exit on any errored or invalid row. Reporting lives in top-level helpers so
# each task body stays within RuboCop's limits.

def fpi_data_source!
  FpiDataSource.existing or abort 'run fpi:bootstrap first'
end

def fpi_payload_dir(path)
  dir, files = FpiPayloadStore.materialize(path)
  puts "fetched #{files.size} file(s) from #{path}: #{files.join(', ')}" if files.any?
  dir
end

def fpi_publish_outcomes(path, out_dir)
  uri = FpiPayloadStore.publish_outcomes(path, out_dir)
  puts "  outcomes published to #{uri}" if uri
end

def report_fpi_preflight(path, facts)
  puts "preflight OK for #{path}"
  puts "  attributes_version: #{facts[:attributes_version]}"
  puts "  shards:             #{facts[:shards].size} (#{facts[:shards].sum { |s| s[:bytes] }} bytes, digests match)"
  puts "  deletions:          #{facts[:deletions] ? 'present' : 'none'}"
  puts "  principal:          #{facts[:principal]}"
end

FPI_TOTAL_LABELS = {
  created: 'created (new upstream record)', applied: 'applied (upstream won)', synced: 'synced (already identical)',
  locally_modified: 'locally modified (local kept)', conflicts_created: 'CONFLICTS raised for review',
  conflicts_updated: 'conflicts refreshed', source_deletion_conflicts: 'source deletions raised',
  tombstone_kept: 'tombstones kept', unknown_deleted: 'unknown deleted', invalid: 'invalid', errored: 'errored'
}.freeze

def report_fpi_totals(totals, data_source)
  FPI_TOTAL_LABELS.each { |key, label| puts format('  %-32<label>s %<count>d', label: label, count: totals[key]) }
  totals.invalid_details.first(10).each { |d| puts "    invalid: #{d}" }
  totals.error_details.first(10).each { |d| puts "    error:   #{d}" }
  puts "  open conflicts now: #{SyncConflict.where(data_source: data_source, status: 'open').count}"
end

def report_fpi_prediction(prediction, cap)
  return if prediction.nil?

  line = FpiRunPredictor::OUTCOMES.map { |o| "#{o} #{prediction[o]}" }.join(', ')
  puts "  predicted: #{line}  (conflict cap #{cap})"
end

def report_fpi_rebaseline(result, data_source, apply)
  puts "#{apply ? 'RE-BASELINED' : 'DRY RUN'} #{data_source.name}: #{result.plants} plants"
  puts "  added keys:   #{result.added.join(', ').presence || '(none)'}"
  puts "  removed keys: #{result.removed.join(', ').presence || '(none)'}"
  puts "  snapshots #{apply ? 'changed' : 'to change'}: #{result.changed}"
  puts "  backup table: #{result.backup_table}" if result.backup_table
end

namespace :fpi do
  desc 'Mirror the FPI organization from the IdP and create its DataSource (idempotent)'
  task bootstrap: :environment do
    org_id = ENV['FPI_ORG_ID'].presence || FpiDataSource::DEFAULT_ORGANIZATION_ID
    org = Organization.mirror_real!(external_id: org_id, name: FpiDataSource::NAME)
    ds = FpiDataSource.find_or_create!(organization: org)
    puts "DataSource #{ds.persisted? ? 'ready' : 'FAILED'}: #{ds.name} (#{ds.source_system_key})"
    puts "  id:           #{ds.id}"
    puts "  organization: #{org.name} (#{org.id}, idp #{org.external_idp_id})"
    puts "  principal:    #{ds.service_principal!.email}"
    puts "  governs #{FpiDataSource::PLANT_ATTRIBUTES.size} plant attributes, version #{FpiDataSource::PLANT_ATTRIBUTES_VERSION}"
  end
end

namespace :fpi do
  desc 'Check everything a run needs without sending a row'
  task :preflight, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails fpi:preflight[path/to/payload-dir | s3://bucket/fpi/payloads/<run_id>]'
    facts = FpiSyncRun.new(data_source: fpi_data_source!, payload_dir: fpi_payload_dir(path), run_id: 'preflight').preflight!
    report_fpi_preflight(path, facts)
  rescue FpiSyncRun::PreflightFailed, FpiPayloadStore::NotFound => e
    abort "preflight FAILED: #{e.message}"
  end
end

namespace :fpi do
  desc 'Sync FPI plants from a payload directory (dry run unless APPLY=true)'
  task :sync_plants, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails fpi:sync_plants[path/to/payload-dir | s3://bucket/fpi/payloads/<run_id>]'
    data_source = fpi_data_source!
    apply = ENV['APPLY'] == 'true'
    run_id = ENV['RUN_ID'].presence || (apply ? abort('RUN_ID is required with APPLY=true; the connector supplies it') : "dry-#{SecureRandom.hex(4)}")

    puts "#{apply ? 'SYNCING' : 'DRY RUN'} #{path} as run #{run_id}  (data source #{data_source.name}, #{data_source.id})"
    cap = ENV['CONFLICT_CAP'].presence&.to_i || FpiSyncRun::DEFAULT_CONFLICT_CAP
    out_dir = ENV['OUT_DIR'].presence || Rails.root.join('tmp', 'fpi', run_id)
    totals = FpiSyncRun.new(data_source: data_source, payload_dir: fpi_payload_dir(path), run_id: run_id, apply: apply,
                            out_dir: out_dir, conflict_cap: cap).run
    puts "  shards / rows: #{totals.shards} / #{totals.rows}"
    report_fpi_prediction(totals.prediction, cap)
    next puts('  dry run: every row built, nothing sent') unless apply

    report_fpi_totals(totals, data_source)
    fpi_publish_outcomes(path, out_dir)
    abort 'sync finished with errored or invalid rows' if FpiSyncRun.failed?(totals)
  rescue FpiSyncRun::PreflightFailed, FpiSyncRun::CapExceeded, FpiPlantFeed::IncompleteRow, FpiPlantFeed::VersionMismatch,
         FpiPayloadStore::NotFound => e
    abort "sync refused: #{e.message}"
  end
end

namespace :fpi do
  desc 'Apply a rulings file to open FPI conflicts (dry run unless APPLY=true)'
  task :resolve_conflicts, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails fpi:resolve_conflicts[path/to/rulings.json]'
    abort "file not found: #{path}" unless File.exist?(path)
    payload = JSON.parse(File.read(path))
    decision = payload['decision'].presence or abort "no 'decision' in #{path}: every rulings file names its decision-log entry"
    reviewer = Principal.find_by(email: payload['reviewer'].to_s) or abort "no principal for reviewer #{payload['reviewer'].inspect}"
    rulings = payload['rulings'] or abort "no 'rulings' in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'APPLYING' : 'DRY RUN'} #{rulings.size} ruling(s) from #{path} (decision #{decision}, reviewer #{reviewer.email})"
    result = FpiConflictRulings.new(data_source: fpi_data_source!, principal: reviewer, decision: decision, apply: apply).apply(rulings)
    { "rulings #{apply ? 'applied' : 'to apply'}" => result.applied, 'conflict not open' => result.not_open,
      'conflict not found for this source' => result.missing, 'refused' => result.refused, 'failed' => result.failed }
      .each { |label, count| puts format('  %-34<label>s %<count>d', label: label, count: count) }
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'rulings finished with failures' if result.failed.positive?
  end
end

namespace :fpi do
  desc 'Remove the plants an FPI run created, across every table (dry run unless APPLY=true)'
  task :rollback, [:run_id] => :environment do |_t, args|
    run_id = args[:run_id].presence
    abort 'usage: bin/rails fpi:rollback[run_id]  (or ALL=true to remove every FPI plant)' if run_id.nil? && ENV['ALL'] != 'true'
    apply = ENV['APPLY'] == 'true'
    plan = FpiRollback.new(data_source: fpi_data_source!, run_id: run_id, apply: apply).run
    puts "#{apply ? 'ROLLED BACK' : 'DRY RUN'} #{run_id ? "run #{run_id}" : 'every FPI plant'}"
    { plants: plan.plants, record_drafts: plan.record_drafts, sync_conflicts: plan.sync_conflicts, images: plan.images, versions: plan.versions }
      .merge(plan.joins).each { |label, count| puts format('  %-24<label>s %<count>d', label: label, count: count) }
    puts '  S3 objects behind image rows are not removed here.' if plan.images.positive?
  end
end

namespace :fpi do
  desc 'Re-stamp every FPI merge base for the current managed attribute set (dry run unless APPLY=true)'
  task rebaseline: :environment do
    data_source = fpi_data_source!
    apply = ENV['APPLY'] == 'true'
    report_fpi_rebaseline(FpiRebaseline.new(data_source: data_source, apply: apply).run, data_source, apply)
  rescue FpiRebaseline::Refused => e
    abort "rebaseline refused: #{e.message}"
  end
end
