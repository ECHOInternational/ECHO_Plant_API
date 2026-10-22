# frozen_string_literal: true

# Publication waves of the FPI plan (tasks API-11 to API-14). Operator guide:
# docs/fpi-publication.md.
#
#   bin/rails publication:report                                   # read-only
#   RULE='{"version":1,...}' bin/rails publication:set_rule          # dry run; APPLY=true writes
#   SELECTOR=quality bin/rails 'publication:publish_wave[fpi-w1]'  # dry run: counts + digest
#   SELECTOR=quality APPLY=true EXPECTED_DIGEST=<sha> bin/rails 'publication:publish_wave[fpi-w1]'
#   bin/rails 'publication:unpublish_wave[fpi-w1]'                  # dry run; APPLY=true restores
#
# SOURCE selects the data source by source_system_key (default fpi).
# SELECTOR is quality (default), remaining or ids (IDS=uuid,uuid,...); LIMIT=N
# keeps the first N by id. NOTES is stored on the wave and may not contain '@'.
#
# Every write task takes the shared ops advisory lock first, dry runs
# included, like the fpi:* tasks: a dry run's digest only means something
# while nothing else is writing. publication:report is read-only and does not.
#
# Output is COUNTS ONLY (this repository's Actions logs are public): wave
# keys, selectors, integers and digests, never a name or an email.

def publication_ops_lock!(task)
  OpsAdvisoryLock.acquire!(task)
rescue OpsAdvisoryLock::Held => e
  abort e.message
end

def publication_data_source!
  key = ENV['SOURCE'].presence || 'fpi'
  DataSource.find_by(source_system_key: key) or abort "no data source with source_system_key #{key.inspect}"
end

def publication_print_counts(counts, indent = '  ')
  counts.each do |label, value|
    if value.is_a?(Hash)
      puts "#{indent}#{label}:"
      publication_print_counts(value, "#{indent}  ")
    else
      puts format('%<indent>s%-34<label>s %<value>s', indent: indent, label: label, value: value)
    end
  end
end

def publication_rule_counts(data_source, new_rule)
  plants = Plant.unscoped.where(data_source_id: data_source.id, deleted_at: nil)
  current = data_source.quality_rule ? plants.where(data_source.quality_rule.sql_condition).count : plants.count
  { 'plants meeting the current rule' => current, 'plants meeting the new rule' => plants.where(new_rule.sql_condition).count }
end

namespace :publication do
  desc 'Report the quality bar and every wave of a data source (read-only)'
  task report: :environment do
    ds = publication_data_source!
    plants = Plant.unscoped.where(data_source_id: ds.id, deleted_at: nil)
    puts "publication report for source #{ds.source_system_key}"
    puts "  rule: #{ds.publication_rule ? JSON.generate(ds.publication_rule) : '(none: every plant meets the bar)'}"
    counts = { 'plants (not deleted)' => plants.count, 'public' => plants.where(access_level: 'public').count,
               'organization access' => plants.where(access_level: 'organization').count }
    counts['meeting the rule'] = plants.where(ds.quality_rule.sql_condition).count if ds.quality_rule
    publication_print_counts(counts)
    PublicationWave.where(data_source: ds).order(:created_at).each do |wave|
      puts "  wave #{wave.key}: #{wave.state}, selector #{wave.selector}, digest #{wave.selection_digest}"
      publication_print_counts(PublicationWaves::Summary.wave(wave), '    ')
    end
  end
end

namespace :publication do
  desc "Set a data source's publication_rule from RULE (JSON; dry run unless APPLY=true)"
  task set_rule: :environment do
    ops_lock = publication_ops_lock!('publication:set_rule')
    ds = publication_data_source!
    rule = JSON.parse(ENV.fetch('RULE') { abort 'RULE is required: the rule as JSON' })
    checked = PublicationRule.new(rule)
    abort "rule refused: #{checked.errors.full_messages.join(', ')}" unless checked.valid?

    apply = ENV['APPLY'] == 'true'
    puts "#{apply ? 'SETTING' : 'DRY RUN'} publication_rule of source #{ds.source_system_key}"
    puts "  current: #{ds.publication_rule ? JSON.generate(ds.publication_rule) : '(none)'}"
    puts "  new:     #{JSON.generate(rule)}"
    publication_print_counts(publication_rule_counts(ds, checked))
    if apply
      PaperTrail.request(whodunnit: PublicationWaves.ops_principal!.id,
                         controller_info: { metadata: { origin: 'set_publication_rule', data_source_id: ds.id } }) do
        ds.update!(publication_rule: rule)
      end
    end
  rescue JSON::ParserError => e
    abort "RULE is not valid JSON: #{e.message}"
  ensure
    ops_lock&.release
  end
end

namespace :publication do
  desc 'Publish a wave of private plants and their images (dry run unless APPLY=true)'
  task :publish_wave, [:key] => :environment do |_t, args|
    ops_lock = publication_ops_lock!('publication:publish_wave')
    key = args[:key].presence or abort "usage: SELECTOR=quality bin/rails 'publication:publish_wave[fpi-w1]'"
    apply = ENV['APPLY'] == 'true'
    result = PublicationWaves::Publisher.new(
      data_source: publication_data_source!, key: key, selector: ENV['SELECTOR'].presence || 'quality',
      ids: ENV['IDS'].to_s.split(','), limit: ENV.fetch('LIMIT', nil), expected_digest: ENV.fetch('EXPECTED_DIGEST', nil),
      notes: ENV.fetch('NOTES', nil), apply: apply
    ).run
    verb = if result.applied then 'PUBLISHED'
           elsif result.resumed then 'EXISTING (nothing applied)'
           else 'DRY RUN'
           end
    puts "#{verb} wave #{key}#{" (#{result.wave.state})" if result.wave}"
    puts "  digest: #{result.digest}"
    publication_print_counts(result.counts)
    puts "  apply with: APPLY=true EXPECTED_DIGEST=#{result.digest}" unless apply
  rescue PublicationWaves::Refused, ActiveRecord::RecordInvalid => e
    abort "publish_wave refused: #{e.message}"
  ensure
    ops_lock&.release
  end
end

namespace :publication do
  desc 'Roll a wave back to exactly what it changed (dry run unless APPLY=true)'
  task :unpublish_wave, [:key] => :environment do |_t, args|
    ops_lock = publication_ops_lock!('publication:unpublish_wave')
    key = args[:key].presence or abort "usage: bin/rails 'publication:unpublish_wave[fpi-w1]'"
    result = PublicationWaves::Unpublisher.new(data_source: publication_data_source!, key: key,
                                               apply: ENV['APPLY'] == 'true').run
    puts "#{result.applied ? 'UNPUBLISHED' : 'DRY RUN'} wave #{key} (#{result.wave.state})"
    publication_print_counts(result.counts)
  rescue PublicationWaves::Refused => e
    abort "unpublish_wave refused: #{e.message}"
  ensure
    ops_lock&.release
  end
end
