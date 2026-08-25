# frozen_string_literal: true

require Rails.root.join('lib/ec_variety_importer')

# Creates Plant API varieties from ECHOcommunity. Reasoning and all three guards
# live in lib/ec_variety_importer.rb; the one to remember is that this only ever
# creates, because for varieties the API is the RICHER side.
#
#   bin/rails varieties:import[tmp/varieties.json]              # dry run
#   APPLY=true bin/rails varieties:import[tmp/varieties.json]   # write
namespace :varieties do
  desc 'Create varieties from ECHOcommunity (dry run unless APPLY=true)'
  task :import, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails varieties:import[path/to/varieties.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    org_id = ENV['ECHO_ORG_ID'].presence or abort 'ECHO_ORG_ID is required'
    org = Organization.find_by(id: org_id) or abort "no organization with id #{org_id}"
    owner = ENV.fetch('ECHO_OWNER_EMAIL', 'echo@echonet.org')
    principal = Principal.find_by(email: owner) or abort "no principal for #{owner}"

    payload = JSON.parse(File.read(path))
    varieties = payload['varieties'] or abort "no 'varieties' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'IMPORTING' : 'DRY RUN'} #{varieties.size} varieties"
    puts "  source:       #{payload['source'] || 'unknown'}"
    puts "  organization: #{org.name}"
    puts "  attributed:   #{owner}"
    puts

    result = EcVarietyImporter.new(organization: org, principal: principal,
                                   owner_email: owner, apply: apply).import(varieties)

    result.changes.first(8).each { |c| puts "    #{c}" }
    puts '    ...' if result.changes.size > 8
    puts
    puts "  varieties #{apply ? 'created' : 'to create'}: #{result.created}"
    puts "  already in the API, untouched: #{result.already_present}"
    puts "  parent plant not in the API:   #{result.missing_plants}"
    puts "  skipped, no name:              #{result.no_name}"
    puts "  failed:                        #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'variety import finished with failures' if result.failed.positive?
  end
end
