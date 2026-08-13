# frozen_string_literal: true

require Rails.root.join('lib/ec_visibility_aligner')

# Thin wrapper; the reasoning lives in lib/ec_visibility_aligner.rb.
#
#   bin/rails plants:align_visibility[tmp/status.json]              # dry run
#   APPLY=true bin/rails plants:align_visibility[tmp/status.json]   # write
#
# The status file comes from tools/export_ec_status.py in the migration
# workspace. ECHO_ORG_ID selects the organization whose plants are aligned.
namespace :plants do
  desc 'Align plant visibility with ECHOcommunity status (dry run unless APPLY=true)'
  task :align_visibility, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails plants:align_visibility[path/to/status.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    org_id = ENV['ECHO_ORG_ID'].presence or abort 'ECHO_ORG_ID is required'
    org = Organization.find_by(id: org_id) or abort "no organization with id #{org_id}"

    payload = JSON.parse(File.read(path))
    statuses = payload['statuses'] or abort "no 'statuses' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'ALIGNING' : 'DRY RUN'} against #{statuses.size} " \
         "ECHOcommunity statuses from #{path}"
    puts "  source environment: #{payload['source'] || 'unknown'}"
    puts "  organization:       #{org.name} (#{org.id})"
    puts

    result = EcVisibilityAligner.new(organization: org, statuses: statuses,
                                     apply: apply).align

    result.changes.first(40).each { |c| puts "    #{c}" }
    puts if result.changes.any?
    puts "  #{apply ? 'changed' : 'would change'}: #{result.changed}"
    puts "  already correct: #{result.unchanged}"
    puts "  not in ECHOcommunity (left alone): #{result.absent}"
    puts "  failed: #{result.failed}"
    result.errors.first(20).each { |e| puts "    #{e}" }
    abort 'alignment finished with failures' if result.failed.positive?
  end
end
