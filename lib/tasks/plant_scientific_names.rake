# frozen_string_literal: true

require Rails.root.join('lib/ec_scientific_name_sync')

# Thin wrapper; the reasoning lives in lib/ec_scientific_name_sync.rb.
#
#   bin/rails plants:sync_scientific_names[tmp/sci.json]              # dry run
#   APPLY=true bin/rails plants:sync_scientific_names[tmp/sci.json]   # write
namespace :plants do
  desc 'Promote scientific names from ECHOcommunity (dry run unless APPLY=true)'
  task :sync_scientific_names, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:sync_scientific_names[path/to/sci.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    plants = payload['plants'] or abort "no 'plants' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'SYNCING' : 'DRY RUN'} scientific names for #{plants.size} plants"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    puts

    result = EcScientificNameSync.new(apply: apply).sync(plants)

    result.changes.first(60).each { |c| puts "    #{c}" }
    puts if result.changes.any?
    puts "  names #{apply ? 'changed' : 'to change'}: #{result.changed}"
    puts "  already correct: #{result.unchanged}"
    puts "  blank incoming, skipped: #{result.blank_skipped}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'scientific name sync finished with failures' if result.failed.positive?
  end
end
