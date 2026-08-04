# frozen_string_literal: true

require 'digest'
require 'json'

# Builds a synthetic identity mapping for rehearsing the S7 cleanup on staging.
#
# Staging was never backfilled: ~2,680 owned records and zero organizations. The
# NOT NULL migration cannot apply there, so nothing downstream of it can be
# tested either. The real backfill needs the IdP identity export, which is PII
# and is deliberately not retained after a run (rollout.md).
#
# For a rehearsal the real uids do not matter -- they exist to match real JWTs,
# and nothing logs into staging with a production token. What matters is the
# SHAPE: every owner resolved to a principal that carries an external_uid, each
# with a personal organization, so staging ends up structurally like production
# rather than like a pre-backfill database.
#
# So this fabricates uids. That is only ever acceptable in staging, and it is
# guarded twice, neither guard sufficient alone:
#
#   1. The ops workflow refuses the action unless environment=staging.
#   2. write! below refuses any database but Plant_API_staging.
#
# Guard 2 is the load-bearing one: it asks the live connection what database it
# is attached to, so it holds even when the task is invoked by hand with the
# wrong credentials.
module StagingRehearsalMapping
  STAGING_DATABASE = 'Plant_API_staging'
  # Kept out of `users` on purpose so the backfill routes it down its
  # shared-email path to a service principal, exactly as it did in production.
  SHARED_EMAILS = ['echo@echonet.org'].freeze
  ECHO_ORG_ID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0001'
  PATH = '/tmp/staging_rehearsal_mapping.json'
  OWNED_TABLES = %w[plants varieties specimens locations categories].freeze

  module_function

  def write!
    guard_staging!
    users = owner_emails.map { |email| user_entry(email) }
    File.write(PATH, JSON.pretty_generate(
                       'users' => users,
                       'organizations' => [{ 'id' => ECHO_ORG_ID, 'name' => 'ECHO (staging rehearsal)' }]
                     ))
    users
  end

  def guard_staging!
    current = ActiveRecord::Base.connection.current_database
    return if current == STAGING_DATABASE

    raise 'REFUSING: the staging rehearsal fabricates identities and runs only against ' \
          "#{STAGING_DATABASE}. Connected to: #{current.inspect}"
  end

  def owner_emails
    connection = ActiveRecord::Base.connection
    OWNED_TABLES.flat_map do |table|
      %w[owned_by created_by].flat_map do |column|
        connection.select_values(
          "SELECT DISTINCT #{column} FROM #{table} WHERE #{column} IS NOT NULL AND #{column} <> ''"
        )
      end
    end.uniq - SHARED_EMAILS
  end

  # Deterministic, so re-running the rehearsal reuses the same identity rather
  # than minting a second one for the same person.
  def user_entry(email)
    digest = Digest::SHA256.hexdigest("staging-rehearsal:#{email}")
    uid = [digest[0, 8], digest[8, 4], "4#{digest[13, 3]}",
           "8#{digest[17, 3]}", digest[20, 12]].join('-')
    { 'uid' => uid, 'email' => email, 'name' => email.split('@').first }
  end
end
