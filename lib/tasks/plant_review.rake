# frozen_string_literal: true

require Rails.root.join('lib/ec_review_applier')

# Thin wrapper; reasoning and guards live in lib/ec_review_applier.rb.
#
#   bin/rails plants:apply_review[tmp/rulings.json]              # dry run
#   APPLY=true bin/rails plants:apply_review[tmp/rulings.json]   # write
#
# Payload: {"decision": "D-054", "rulings": [
#   {"plant_id": "<uuid>", "locale": "es", "attribute": "uses", "value": "..."}]}
#
# This OVERWRITES, which the backfill never does — every payload names the
# decision-log entry that authorised it, and the log is where the ruling and
# its exceptions live.

# Reporting lives outside the namespace block so the task body stays within
# RuboCop's BlockLength and AbcSize limits, matching variety_publish.rake.
def report_review_changes(result)
  result.changes.first(30).each { |c| puts "    #{c}" }
  puts '    ...' if result.changes.size > 30
  puts
end

def report_review_counts(result, apply)
  { "values #{apply ? 'applied' : 'to apply'}" => result.applied,
    'already identical, untouched' => result.already_applied,
    'blank incoming, refused' => result.blank_refused,
    'attribute not governed, refused' => result.not_governed,
    'plants not in this database' => result.missing_plants,
    'failed' => result.failed }.each do |label, count|
    puts format('  %-33<label>s %<count>d', label: label, count: count)
  end
  result.errors.first(20).each { |e| puts "    #{e}" }
end

namespace :plants do
  desc 'Apply reviewed conflict rulings from the decision log (dry run unless APPLY=true)'
  task :apply_review, [:path] => :environment do |_t, args|
    path = args[:path] or abort 'usage: bin/rails plants:apply_review[path/to/rulings.json]'
    abort "file not found: #{path}" unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    rulings = payload['rulings'] or abort "no 'rulings' key in #{path}"
    decision = payload['decision'] or
      abort "no 'decision' key in #{path} — every review payload must name its decision-log entry"
    apply = ENV['APPLY'] == 'true'

    puts "#{apply ? 'APPLYING' : 'DRY RUN'} #{rulings.size} reviewed rulings (#{decision})"
    puts "  source: #{payload['source'] || 'unknown'}"
    puts

    result = EcReviewApplier.new(apply: apply).apply(rulings)
    report_review_changes(result)
    report_review_counts(result, apply)
    abort 'review apply finished with failures' if result.failed.positive?
  end
end
