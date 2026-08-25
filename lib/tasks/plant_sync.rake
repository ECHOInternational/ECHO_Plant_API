# frozen_string_literal: true

require Rails.root.join('lib/ec_data_source')
require Rails.root.join('lib/ec_plant_feed')

# Runs the ECHOcommunity narrative feed through SourceSynchronizer. The
# reasoning lives in lib/ec_plant_feed.rb; the short version is that this is the
# ENGLISH half of reconciliation, where the genuine conflicts are. Other locales
# are additive and go through plants:backfill_translations instead.
#
#   bin/rails plants:sync_plants[tmp/feed.json]              # dry run
#   APPLY=true bin/rails plants:sync_plants[tmp/feed.json]   # write
#
# Payload: {"plants": {"<uuid>": {"uses": "...", ...}}} — flat, one locale, as
# emitted by tools/export_ec_narrative.py --for feed.
namespace :plants do
  desc 'Sync English plant narrative from ECHOcommunity (dry run unless APPLY=true)'
  task :sync_plants, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails plants:sync_plants[path/to/feed.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    data_source = EcDataSource.existing or abort 'run sync:bootstrap first'
    plants = JSON.parse(File.read(path))['plants'] or abort "no 'plants' key in #{path}"
    apply = ENV['APPLY'] == 'true'
    run_id = ENV['RUN_ID'].presence || SecureRandom.hex(8)

    unlinked = Plant.unscoped.where(id: plants.keys, data_source_id: nil).count
    if unlinked.positive?
      abort "#{unlinked} of these plants are not linked to a data source. " \
            'Run sync:link_plants first, or the synchronizer will create duplicates.'
    end

    puts "#{apply ? 'SYNCING' : 'DRY RUN'} #{plants.size} plants, locale en"
    puts "  data source: #{data_source.name} (#{data_source.id})"
    puts "  run id:      #{run_id}"
    puts

    result = EcPlantFeed.new(data_source: data_source, run_id: run_id)
                        .run(plants, apply: apply)
    report = result.report
    unless report
      puts "  rows built: #{result.rows.size} (dry run, nothing sent)"
      next
    end

    puts "  applied (upstream won):        #{report.applied}"
    puts "  synced (already identical):    #{report.synced}"
    puts "  locally modified (local kept): #{report.locally_modified}"
    puts "  CONFLICTS raised for review:   #{report.conflicts_created}"
    puts "  conflicts refreshed:           #{report.conflicts_updated}"
    puts "  created (new upstream record): #{report.created}"
    puts "  invalid:                       #{report.invalid}"
    puts "  errored:                       #{report.errored}"
    report.invalid_details.first(10).each { |d| puts "    invalid: #{d}" }
    report.error_details.first(10).each { |d| puts "    error:   #{d}" }
    puts
    puts "  open conflicts now: #{SyncConflict.where(status: 'open').count}"
    abort 'sync finished with errors' if report.errored.positive?
  end
end
