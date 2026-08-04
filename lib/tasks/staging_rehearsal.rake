# frozen_string_literal: true

require Rails.root.join('lib/staging_rehearsal_mapping')

# Staging-only tooling for rehearsing the S7 cleanup against prod-sized data.
# The reasoning, and both guards, live in lib/staging_rehearsal_mapping.rb.
namespace :ownership do
  desc 'STAGING ONLY: synthesize an identity mapping from the database itself'
  task synthesize_mapping: :environment do
    users = StagingRehearsalMapping.write!
    puts "MAPPING_SYNTHESIZED users=#{users.size}"
    puts "MAPPING_PATH #{StagingRehearsalMapping::PATH}"
    puts "ECHO_ORG_ID #{StagingRehearsalMapping::ECHO_ORG_ID}"
  rescue RuntimeError => e
    abort e.message
  end

  desc 'STAGING ONLY: synthesize a mapping and back-fill with it (DRY_RUN=1 by default)'
  task staging_rehearsal: :environment do
    Rake::Task['ownership:synthesize_mapping'].invoke

    ENV['MAPPING'] = StagingRehearsalMapping::PATH
    ENV['ECHO_ORG_ID'] = StagingRehearsalMapping::ECHO_ORG_ID
    ENV['DRY_RUN'] = ENV.fetch('DRY_RUN', '1')
    puts "\nRunning ownership:backfill with the synthesized mapping (DRY_RUN=#{ENV.fetch('DRY_RUN')})"
    Rake::Task['ownership:backfill'].invoke
  end
end
