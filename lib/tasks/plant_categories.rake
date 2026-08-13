# frozen_string_literal: true

require Rails.root.join('lib/ec_category_importer')

# Thin wrapper; the reasoning lives in lib/ec_category_importer.rb.
#
#   bin/rails plants:import_categories[tmp/categories.json]              # dry run
#   APPLY=true bin/rails plants:import_categories[tmp/categories.json]   # write
namespace :plants do
  desc 'Create missing categories and sync membership (dry run unless APPLY=true)'
  task :import_categories, [:path] => :environment do |_t, args|
    path = args[:path] or
      abort 'usage: bin/rails plants:import_categories[path/to/categories.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    owner = ENV.fetch('ECHO_OWNER_EMAIL', 'echo@echonet.org')
    org_id = ENV['ECHO_ORG_ID'].presence or abort 'ECHO_ORG_ID is required'
    org = Organization.find_by(id: org_id) or abort "no organization with id #{org_id}"

    principal = if ENV['ECHO_PRINCIPAL_ID'].present?
                  Principal.find_by(id: ENV['ECHO_PRINCIPAL_ID'])
                else
                  Principal.find_by(email: owner, kind: 'service')
                end
    principal or abort 'no principal found (set ECHO_PRINCIPAL_ID, or create a ' \
                       "service principal for #{owner})"

    payload = JSON.parse(File.read(path))
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'IMPORTING' : 'DRY RUN'} #{payload['categories'].size} categories " \
         "and membership for #{payload['membership'].size} plants"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    puts "  organization:       #{org.name} (#{org.id})"
    puts

    result = EcCategoryImporter.new(organization: org, principal: principal,
                                    owner_email: owner, apply: apply)
                               .import(payload['categories'], payload['membership'])

    puts "  categories #{apply ? 'created' : 'to create'}: #{result.categories_created}"
    puts "  categories already present: #{result.categories_present}"
    puts "  links #{apply ? 'created' : 'to create'}: #{result.links_created}"
    puts "  links already present: #{result.links_present}"
    puts "  plants not in this database: #{result.missing_plants}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'category import finished with failures' if result.failed.positive?
  end
end
