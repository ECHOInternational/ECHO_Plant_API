# frozen_string_literal: true

require Rails.root.join('lib/staging_org_repoint')

# Re-points STAGING ownership from placeholder organization ids to the
# ECHOcommunity staging organization ids (see lib/staging_org_repoint.rb).
#
#   bin/rails orgs:repoint_staging                     dry run, built-in staging mapping
#   bin/rails orgs:repoint_staging APPLY=true CONFIRM=REPOINT-STAGING-ORGS
#   bin/rails orgs:repoint_staging REVERSE=true ...    the mapping inverted (rollback)
#   FROM=<uuid> TO=<uuid>, or MAPPING="from:to,from:to", replace the built-in mapping.
#
# Refuses RAILS_ENV=production and any database but Plant_API_staging, dry run
# included. APPLY takes the shared ops advisory lock, so it never interleaves
# with an fpi:* or publication:* write task. Prints ids and counts only.
namespace :orgs do
  desc 'Re-point staging organization ids to the ECHOcommunity staging ids (dry run unless APPLY=true)'
  task repoint_staging: :environment do
    apply = ENV['APPLY'] == 'true'
    mapping = StagingOrgRepoint.mapping_from_env(ENV)
    StagingOrgRepoint.guard!(apply: apply, confirm: ENV.fetch('CONFIRM', nil))
    lock = OpsAdvisoryLock.acquire!('orgs:repoint_staging') if apply
    StagingOrgRepoint.new(mapping: mapping, apply: apply).run
  rescue StagingOrgRepoint::Refused, OpsAdvisoryLock::Held => e
    abort e.message
  ensure
    lock&.release
  end
end
