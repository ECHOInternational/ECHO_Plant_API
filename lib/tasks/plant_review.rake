# frozen_string_literal: true

require Rails.root.join('lib/ec_review_applier')

# Thin wrapper; reasoning and guards live in lib/ec_review_applier.rb.
#
#   bin/rails plants:apply_review[tmp/rulings.json]              # dry run
#   APPLY=true bin/rails plants:apply_review[tmp/rulings.json]   # write
#
# Payload: {"decision": "D-054", "rulings": [
#   {"plant_id": "<uuid>", "locale": "es", "attribute": "uses", "value": "..."},
#   {"plant_id": "<uuid>", "attribute": "optimal_altitude_range", "lo": 1500, "hi": null},
#   {"plant_id": "<uuid>", "attribute": "has_edible_mature_fruit",
#    "flag": true, "was": false}]}
#
# 'was' is optional and flag-only: the value the review page showed. If the
# database has moved on since the ruling, the row is refused, not overwritten.
#
# This OVERWRITES, which the backfill never does — every payload names the
# decision-log entry that authorised it, and the log is where the ruling and
# its exceptions live. That decision rides into each PaperTrail version's
# metadata, so the history points back at the ruling; the writes are attributed
# to ECHO_OWNER_EMAIL (default echo@echonet.org), matching variety_restore.

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
    'range already held, refused' => result.range_occupied,
    'changed since review, refused' => result.stale_refused,
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
    owner = ENV.fetch('ECHO_OWNER_EMAIL', 'echo@echonet.org')
    principal = Principal.find_by(email: owner) or abort "no principal for #{owner}"

    puts "#{apply ? 'APPLYING' : 'DRY RUN'} #{rulings.size} reviewed rulings (#{decision})"
    puts "  source: #{payload['source'] || 'unknown'}"
    puts "  attributed to: #{owner} (origin: review-apply, decision: #{decision})"
    puts

    result = EcReviewApplier.new(principal: principal, decision: decision,
                                 apply: apply).apply(rulings)
    report_review_changes(result)
    report_review_counts(result, apply)
    abort 'review apply finished with failures' if result.failed.positive?
  end
end
