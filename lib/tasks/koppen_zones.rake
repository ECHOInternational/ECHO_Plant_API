# frozen_string_literal: true

require Rails.root.join('lib/koppen_zone_seeder')

# Seeds the Köppen-Geiger climate zones. The list and its reasoning live in
# lib/koppen_zone_seeder.rb.
#
#   bin/rails koppen:seed              # dry run
#   APPLY=true bin/rails koppen:seed   # write
#
# Idempotent: safe to re-run after a deploy.
namespace :koppen do
  desc 'Seed the Köppen climate zone lookup (dry run unless APPLY=true)'
  task seed: :environment do
    apply = ENV['APPLY'] == 'true'
    puts "#{apply ? 'SEEDING' : 'DRY RUN'} #{KoppenZoneSeeder::ALL.size} Köppen zones"
    puts "  source:  #{KoppenZoneSeeder::SOURCE}"
    puts "  version: #{KoppenZoneSeeder::VERSION}"
    puts

    result = KoppenZoneSeeder.new(apply: apply).seed

    puts "  zones #{apply ? 'created' : 'to create'}: #{result.created}"
    puts "  zones #{apply ? 'updated' : 'to update'}: #{result.updated}"
    puts "  already correct: #{result.unchanged}"
    next unless apply

    puts
    puts "  groups:    #{KoppenZone.groups.count}"
    puts "  subgroups: #{KoppenZone.subgroups.count}"
    puts "  classes:   #{KoppenZone.classes.count}"
    puts "  in Beck 2018: #{KoppenZone.authoritative.count}"
    orphans = KoppenZone.where(parent_id: nil).where.not(level: 'group').count
    puts "  non-group zones without a parent: #{orphans}"
    abort 'seeding left unparented zones' if orphans.positive?
  end
end
