# frozen_string_literal: true

require Rails.root.join('lib/ec_taxonomy_importer')

# Thin wrapper; the reasoning and both guards live in
# lib/ec_taxonomy_importer.rb.
#
#   bin/rails plants:import_taxonomies[tmp/tax.json]              # dry run
#   APPLY=true bin/rails plants:import_taxonomies[tmp/tax.json]   # write
#
# Payload as emitted by tools/export_ec_taxonomies.py:
#   {"taxonomies": {"tolerances": {"<plant uuid>": ["<lookup uuid>"]}}}
namespace :plants do
  desc 'Import antinutrient/tolerance/growth-habit assignments (dry run unless APPLY=true)'
  task :import_taxonomies, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:import_taxonomies[path/to/tax.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    taxonomies = payload['taxonomies'] or abort "no 'taxonomies' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'IMPORTING' : 'DRY RUN'} #{taxonomies.keys.join(', ')}"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    taxonomies.each { |k, v| puts "  #{k}: #{(v || {}).size} plants" }
    puts

    result = EcTaxonomyImporter.new(apply: apply).import(taxonomies)

    puts "  links #{apply ? 'created' : 'to create'}: #{result.linked}"
    puts "  links already present: #{result.present}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  unknown lookup uuids: #{result.unknown_lookups.size}"
    result.unknown_lookups.first(10).each { |u| puts "    #{u}" }
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'taxonomy import finished with failures' if result.failed.positive?
    abort 'payload names lookup uuids that do not exist' if result.unknown_lookups.any?
  end
end
