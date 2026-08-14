# frozen_string_literal: true

require Rails.root.join('lib/ec_koppen_zone_importer')

# Thin wrapper; the reasoning and both guards live in
# lib/ec_koppen_zone_importer.rb.
#
#   bin/rails plants:import_koppen_zones[tmp/zones.json]              # dry run
#   APPLY=true bin/rails plants:import_koppen_zones[tmp/zones.json]   # write
#
# Payload shape: {"plants": {"<uuid>": ["Cfa", "Aw"]}}
namespace :plants do
  desc 'Import plant climate-zone assignments from ECHOcommunity (dry run unless APPLY=true)'
  task :import_koppen_zones, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:import_koppen_zones[path/to/zones.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    plants = payload['plants'] or abort "no 'plants' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'IMPORTING' : 'DRY RUN'} climate zones for #{plants.size} plants"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    puts

    result = EcKoppenZoneImporter.new(apply: apply).import(plants)

    puts "  links #{apply ? 'created' : 'to create'}: #{result.linked}"
    puts "  links already present: #{result.present}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  unknown zone codes: #{result.unknown_zones.size}"
    result.unknown_zones.each { |c| puts "    #{c.inspect}" }
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'climate zone import finished with failures' if result.failed.positive?
    abort 'payload names zone codes that are not seeded' if result.unknown_zones.any?
  end
end
