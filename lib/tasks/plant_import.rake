# frozen_string_literal: true

require Rails.root.join('lib/ec_plant_importer')

# Thin wrapper: the import logic and its reasoning live in
# lib/ec_plant_importer.rb, following the pattern of staging_rehearsal.rake.
#
#   bin/rails plants:import[tmp/import.json]              # dry run
#   APPLY=true bin/rails plants:import[tmp/import.json]   # actually write
#
# ECHO_ORG_ID selects the owning organization and differs between environments;
# staging uses StagingRehearsalMapping::ECHO_ORG_ID.
namespace :plants do
  desc 'Import ECHOcommunity plants from a seed-format JSON file (dry run unless APPLY=true)'
  task :import, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails plants:import[path/to/file.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    owner = ENV.fetch('ECHO_OWNER_EMAIL', 'echo@echonet.org')
    org_id = ENV['ECHO_ORG_ID'].presence or
      abort 'ECHO_ORG_ID is required (the owning organization for imported plants)'

    org = Organization.find_by(id: org_id) or abort "no organization with id #{org_id}"

    # created_by_principal_id is NOT NULL, and a `real` organization such as
    # ECHO has no principal of its own -- only `personal` orgs do. Production
    # attributes its 322 seeded plants to the SERVICE principal for
    # echo@echonet.org, so default to matching that.
    principal = if ENV['ECHO_PRINCIPAL_ID'].present?
                  Principal.find_by(id: ENV['ECHO_PRINCIPAL_ID'])
                else
                  Principal.find_by(email: owner, kind: 'service')
                end
    principal or abort 'no principal found (set ECHO_PRINCIPAL_ID, or create a ' \
                       "service principal for #{owner})"

    apply = ENV['APPLY'] == 'true'
    records = JSON.parse(File.read(path))

    puts "#{apply ? 'IMPORTING' : 'DRY RUN'} #{records.size} plants from #{path}"
    puts "  owning organization:  #{org.name} (#{org.id})"
    puts "  owned_by:             #{owner}"
    puts "  created_by_principal: #{principal.email} (#{principal.kind})"
    puts

    result = EcPlantImporter.new(organization: org, principal: principal,
                                 owner_email: owner, apply: apply).import(records)

    puts "  #{apply ? 'created' : 'would create'}: #{result.created}"
    puts "  skipped (already present): #{result.skipped}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'import finished with failures' if result.failed.positive?
  end
end
