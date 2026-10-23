# frozen_string_literal: true

# Parses MOBILE_FULL_SYNC_OWNER_ORG_IDS: the organizations whose plants the
# frozen mobile app may receive from an unpaginated plants() call (see
# MobileFullSyncGuard). Required by config/initializers/mobile_full_sync.rb.
#
# The value is a comma-separated list of organization UUIDs. Unset or blank
# means the environment's default. Anything malformed also means the default:
# this list narrows what an unpaginated call returns, so a typo must never
# widen it (an empty list would hide everything; a half-parsed one could hide
# ECHO). Failing closed to the ECHO organization keeps the mobile app's
# behavior exactly what it is today.
#
# The default is per Rails environment, because organization UUIDs differ
# between environments: staging has its own ECHO organization. Keying the
# default on RAILS_ENV (which every task definition already sets) means a
# deploy needs no new task-definition variable; the variable stays available
# as an explicit override. Development and test use the production default,
# because local databases are copies of production.
module MobileFullSyncConfig
  ENV_NAME = 'MOBILE_FULL_SYNC_OWNER_ORG_IDS'

  # The production ECHO organization (a mirrored real organization; its local
  # primary key is the IdP UUID).
  DEFAULT_OWNER_ORG_IDS = ['99ee034e-6a85-44fc-a366-cb6dbc637783'].freeze

  # The staging ECHO organization: ECHOcommunity staging's "echo". Staging
  # adopted the IdP ids on 2026-10-23 (orgs:repoint_staging), replacing the
  # S7 rehearsal placeholder aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0001.
  STAGING_OWNER_ORG_IDS = ['149f6971-b63a-45e7-be7f-e67fc7d7b3d6'].freeze

  DEFAULTS_BY_ENV = { 'staging' => STAGING_OWNER_ORG_IDS }.freeze

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  module_function

  def default_for(env)
    DEFAULTS_BY_ENV.fetch(env.to_s, DEFAULT_OWNER_ORG_IDS)
  end

  def parse(raw, env: nil, logger: nil)
    default = default_for(env)
    return default if raw.blank?

    ids = raw.split(',', -1).map { |entry| entry.strip.downcase }
    return ids.uniq.freeze if ids.all? { |id| UUID_FORMAT.match?(id) }

    logger&.warn("#{ENV_NAME} is malformed; falling back to the default allow-list")
    default
  end
end
