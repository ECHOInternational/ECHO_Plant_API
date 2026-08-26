# frozen_string_literal: true

require Rails.root.join('lib/ec_variety_restorer')

# Un-deletes named varieties and returns them to the public set. Uuids are
# passed as arguments, never read from a generated file, so that reversing a
# curator's deletion is always a deliberate act. Reasoning lives in
# lib/ec_variety_restorer.rb.
#
#   bin/rails varieties:restore[uuid]                # dry run
#   APPLY=true bin/rails varieties:restore[uuid,uuid] # write
namespace :varieties do
  desc 'Un-delete named varieties and publish them (dry run unless APPLY=true)'
  task :restore, [:uuids] => :environment do |_t, args|
    uuids = (args.extras + [args[:uuids]]).compact.reject(&:empty?)
    abort 'usage: bin/rails varieties:restore[uuid,uuid]' if uuids.empty?

    owner = ENV.fetch('ECHO_OWNER_EMAIL', 'echo@echonet.org')
    principal = Principal.find_by(email: owner) or abort "no principal for #{owner}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'RESTORING' : 'DRY RUN'} over #{uuids.size} varieties"
    puts "  attributed to: #{owner} (origin: migration-restore)"
    puts

    result = EcVarietyRestorer.new(principal: principal, apply: apply).restore(uuids)

    result.changes.each { |c| puts "    #{c}" }
    puts
    puts "  varieties #{apply ? 'restored' : 'to restore'}: #{result.restored}"
    puts "  not deleted, left alone:   #{result.not_deleted}"
    puts "  not in the API:            #{result.missing}"
    puts "  failed:                    #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'variety restore finished with failures' if result.failed.positive?
  end
end
