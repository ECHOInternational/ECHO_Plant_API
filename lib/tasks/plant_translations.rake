# frozen_string_literal: true

require Rails.root.join('lib/ec_translation_backfill')

# Thin wrapper; the reasoning and all three guards live in
# lib/ec_translation_backfill.rb.
#
#   bin/rails plants:backfill_translations[tmp/tr.json]              # dry run
#   APPLY=true bin/rails plants:backfill_translations[tmp/tr.json]   # write
#
# Payload: {"plants": {"<uuid>": {"es": {"uses": "..."}}}}
#
# CONFLICTS ARE NOT RESOLVED HERE. Where the API already holds different text
# the run reports it and writes nothing; that list is the review pile.
namespace :plants do
  desc 'Backfill narrative text into locales the API lacks (dry run unless APPLY=true)'
  task :backfill_translations, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:backfill_translations[path/to/tr.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    plants = payload['plants'] or abort "no 'plants' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'BACKFILLING' : 'DRY RUN'} translations for #{plants.size} plants"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    puts

    result = EcTranslationBackfill.new(apply: apply).backfill(plants)

    puts "  values #{apply ? 'written' : 'to write'}: #{result.written}"
    puts "  already identical: #{result.already_present}"
    puts "  blank incoming, skipped: #{result.blank_skipped}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    puts
    puts "  DIFFERENT on both sides, left untouched for review: #{result.differs}"
    result.conflicts.first(30).each do |c|
      puts "    #{c[:plant]} [#{c[:locale]}] #{c[:attribute]}: " \
           "api #{c[:api_length]} chars vs ECHOcommunity #{c[:ec_length]}"
    end
    abort 'translation backfill finished with failures' if result.failed.positive?
  end
end
