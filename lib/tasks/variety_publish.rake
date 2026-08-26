# frozen_string_literal: true

require Rails.root.join('lib/ec_variety_publisher')

# Publishes varieties ECHOcommunity already publishes but the API keeps
# organization-only. Reasoning and all four guards live in
# lib/ec_variety_publisher.rb; the one to remember is that a soft-deleted
# variety is never resurrected.
#
#   bin/rails varieties:publish[tmp/vanish.json]              # dry run
#   APPLY=true bin/rails varieties:publish[tmp/vanish.json]   # write

# Reporting lives outside the namespace block so the task body stays within
# RuboCop's BlockLength and AbcSize limits.
def report_variety_changes(result)
  result.changes.first(30).each { |c| puts "    #{c}" }
  puts '    ...' if result.changes.size > 30
  puts
end

def report_variety_counts(result, apply)
  {
    "varieties #{apply ? 'published' : 'to publish'}" => result.published,
    'already public, untouched' => result.already_public,
    'soft-deleted, NOT resurrected' => result.deleted,
    'not ECHO-owned, left alone' => result.not_echo_owned,
    'not in the API' => result.missing,
    'failed' => result.failed
  }.each { |label, count| puts format('  %-31<label>s %<count>d', label: label, count: count) }
  result.errors.first(20).each { |e| puts "    #{e}" }
end

namespace :varieties do
  desc 'Publish organization-only varieties EC publishes (dry run unless APPLY=true)'
  task :publish, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails varieties:publish[path/to/ids.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    org_id = ENV['ECHO_ORG_ID'].presence or abort 'ECHO_ORG_ID is required'
    org = Organization.find_by(id: org_id) or abort "no organization with id #{org_id}"

    payload = JSON.parse(File.read(path))
    uuids = payload['variety_ids'] or abort "no 'variety_ids' key in #{path}"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'PUBLISHING' : 'DRY RUN'} over #{uuids.size} varieties"
    puts "  source:       #{payload['source'] || 'unknown'}"
    puts "  organization: #{org.name}"
    puts

    result = EcVarietyPublisher.new(organization: org, apply: apply).publish(uuids)
    report_variety_changes(result)
    report_variety_counts(result, apply)
    abort 'variety publish finished with failures' if result.failed.positive?
  end
end
