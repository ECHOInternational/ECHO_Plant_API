# frozen_string_literal: true

require Rails.root.join('lib/ownership_repair')

# Repairs the records `ownership:preflight` reports as unreachable. See
# lib/ownership_repair.rb for what is being repaired and why.
#
#   REPAIR_MAPPING  local path OR s3:// URI to the repair config JSON
#   DRY_RUN         1 (default) reports the plan and writes nothing
#
# The config carries personal data and is supplied at runtime from a private
# source; it is deliberately not in this repository, which is public. Same
# treatment as ownership:backfill's MAPPING (rollout.md).
def print_repair_report(report, dry_run)
  puts "\nLINK -- give these records an owner who can actually sign in"
  report[:link].each { |line| puts "  #{line}" }

  puts "\nPURGE -- confirmed disposable by the account holder"
  report[:purge].each { |line| puts "  #{line}" }

  puts "\n#{'=' * 60}"
  if dry_run
    puts 'DRY RUN complete. Nothing was written. Re-run with DRY_RUN=0 to apply.'
  else
    puts "Owners linked: #{report[:linked]}"
    puts "Records purged: #{report[:purged].inspect}"
  end

  if report[:refused].any?
    puts "\nREFUSED (#{report[:refused].size}) -- left untouched on purpose, look at these:"
    report[:refused].each { |line| puts "  #{line}" }
  end
  puts 'Addresses are shown redacted; this log is public. Re-run ownership:preflight to confirm.'
end

namespace :ownership do
  desc 'Repair unreachable ownership from a private REPAIR_MAPPING config (DRY_RUN=1 default)'
  task repair_unreachable: :environment do
    mapping_env = ENV.fetch('REPAIR_MAPPING', nil)
    abort 'ERROR: REPAIR_MAPPING env var is required (local path or s3:// URI)' if mapping_env.blank?

    dry_run = ENV.fetch('DRY_RUN', '1') != '0'
    puts 'ownership:repair_unreachable'
    puts "MODE #{dry_run ? 'DRY RUN -- nothing will be written' : 'WRITING'}"
    puts '=' * 60

    report = with_mapping_path(mapping_env) do |path|
      config = OwnershipRepair.load_config(path)
      puts "Config: #{config.link.size} to link, #{config.purge.size} to purge"
      OwnershipRepair.run!(config, dry_run: dry_run)
    end

    print_repair_report(report, dry_run)
  end
end
