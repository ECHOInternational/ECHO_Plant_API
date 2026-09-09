# frozen_string_literal: true

require Rails.root.join('lib/fpi_data_source')
require Rails.root.join('lib/fpi_plant_feed')
require Rails.root.join('lib/fpi_sync_run')
require Rails.root.join('lib/fpi_rebaseline')

# The Food Plants International import (fpi-connector plan, milestone M2).
#
#   bin/rails fpi:bootstrap                        # mirror the FPI organization, create the DataSource (idempotent)
#   bin/rails fpi:preflight[path/to/payload]        # everything a run needs, sends nothing
#   bin/rails fpi:sync_plants[path/to/payload]      # dry run: build every row, send nothing
#   APPLY=true RUN_ID=<id> bin/rails fpi:sync_plants[path/to/payload]
#   bin/rails fpi:rebaseline                        # dry run; APPLY=true to write, after bumping PLANT_ATTRIBUTES_VERSION
#
# One convention for the namespace: a path argument, dry run by default and
# APPLY=true to write, RUN_ID supplied by the connector (never random on a
# real run), non-zero exit on any errored or invalid row. Reporting lives in
# top-level helpers so each task body stays within RuboCop's limits.

def fpi_data_source!
  FpiDataSource.existing or abort 'run fpi:bootstrap first'
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
    path = args[:path] or abort 'usage: bin/rails fpi:preflight[path/to/payload-dir]'
    facts = FpiSyncRun.new(data_source: fpi_data_source!, payload_dir: path, run_id: 'preflight').preflight!
    report_fpi_preflight(path, facts)
  rescue FpiSyncRun::PreflightFailed => e
    abort "preflight FAILED: #{e.message}"
  end
end

namespace :fpi do
  desc 'Sync FPI plants from a payload directory (dry run unless APPLY=true)'
  task :sync_plants, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails fpi:sync_plants[path/to/payload-dir]'
    data_source = fpi_data_source!
    apply = ENV['APPLY'] == 'true'
    run_id = ENV['RUN_ID'].presence || (apply ? abort('RUN_ID is required with APPLY=true; the connector supplies it') : "dry-#{SecureRandom.hex(4)}")

    puts "#{apply ? 'SYNCING' : 'DRY RUN'} #{path} as run #{run_id}  (data source #{data_source.name}, #{data_source.id})"
    totals = FpiSyncRun.new(data_source: data_source, payload_dir: path, run_id: run_id, apply: apply, out_dir: ENV['OUT_DIR'].presence).run
    puts "  shards / rows: #{totals.shards} / #{totals.rows}"
    next puts('  dry run: every row built, nothing sent') unless apply

    report_fpi_totals(totals, data_source)
    abort 'sync finished with errored or invalid rows' if FpiSyncRun.failed?(totals)
  rescue FpiSyncRun::PreflightFailed, FpiPlantFeed::IncompleteRow, FpiPlantFeed::VersionMismatch => e
    abort "sync refused: #{e.message}"
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
