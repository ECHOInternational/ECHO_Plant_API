# frozen_string_literal: true

require Rails.root.join('lib/plant_description_sync')

# Thin wrapper; the reasoning and all three guards live in
# lib/plant_description_sync.rb.
#
#   bin/rails plants:sync_descriptions[tmp/descriptions.json]              # dry run
#   APPLY=true bin/rails plants:sync_descriptions[tmp/descriptions.json]   # write
#
# Payload shape:
#   {"plants": {"<uuid>": {"en": {"description": "<html>"}}}}
namespace :plants do
  desc 'Write curated plant descriptions from a payload (dry run unless APPLY=true)'
  task :sync_descriptions, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:sync_descriptions[path/to/descriptions.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    plants = payload['plants'] or abort "no 'plants' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'SYNCING' : 'DRY RUN'} descriptions for #{plants.size} plants"
    puts "  source: #{payload['source'] || 'unknown'}"
    puts "  writable fields: #{PlantDescriptionSync::FIELDS.join(', ')}"
    puts

    result = PlantDescriptionSync.new(apply: apply).sync(plants)

    result.changes.each { |c| puts "    #{c}" }
    puts if result.changes.any?
    puts "  fields #{apply ? 'changed' : 'to change'}: #{result.changed}"
    puts "  already correct: #{result.unchanged}"
    puts "  blank incoming, skipped: #{result.blank_skipped}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'description sync finished with failures' if result.failed.positive?
  end
end
