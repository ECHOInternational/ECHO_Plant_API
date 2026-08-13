# frozen_string_literal: true

require Rails.root.join('lib/ec_common_name_sync')

# Thin wrapper; the reasoning lives in lib/ec_common_name_sync.rb.
#
#   bin/rails plants:sync_common_names[tmp/common_names.json]              # dry run
#   APPLY=true bin/rails plants:sync_common_names[tmp/common_names.json]   # write
namespace :plants do
  desc 'Sync common names and primary flags from ECHOcommunity (dry run unless APPLY=true)'
  task :sync_common_names, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:sync_common_names[path/to/common_names.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    plants = payload['plants'] or abort "no 'plants' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'SYNCING' : 'DRY RUN'} common names for #{plants.size} plants"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    puts

    result = EcCommonNameSync.new(apply: apply).sync(plants)

    puts "  names #{apply ? 'created' : 'to create'}: #{result.created}"
    puts "  names already present: #{result.present}"
    puts "  primary set: #{result.primary_set}"
    puts "  primary cleared: #{result.primary_cleared}"
    puts "  names recased to match ECHOcommunity: #{result.recased}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'common name sync finished with failures' if result.failed.positive?
  end
end
