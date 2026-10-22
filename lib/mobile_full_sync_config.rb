# frozen_string_literal: true

# Parses MOBILE_FULL_SYNC_OWNER_ORG_IDS: the organizations whose plants the
# frozen mobile app may receive from an unpaginated plants() call (see
# MobileFullSyncGuard). Required by config/initializers/mobile_full_sync.rb.
#
# The value is a comma-separated list of organization UUIDs. Unset or blank
# means the default. Anything malformed also means the default: this list
# narrows what an unpaginated call returns, so a typo must never widen it
# (an empty list would hide everything; a half-parsed one could hide ECHO).
# Failing closed to the production ECHO organization keeps the mobile app's
# behavior exactly what it is today.
#
# Staging and every non-production environment MUST set the variable: their
# organization UUIDs differ from production's.
module MobileFullSyncConfig
  ENV_NAME = 'MOBILE_FULL_SYNC_OWNER_ORG_IDS'

  # The production ECHO organization (a mirrored real organization; its local
  # primary key is the IdP UUID).
  DEFAULT_OWNER_ORG_IDS = ['99ee034e-6a85-44fc-a366-cb6dbc637783'].freeze

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  module_function

  def parse(raw, logger: nil)
    return DEFAULT_OWNER_ORG_IDS if raw.blank?

    ids = raw.split(',', -1).map { |entry| entry.strip.downcase }
    return ids.uniq.freeze if ids.all? { |id| UUID_FORMAT.match?(id) }

    logger&.warn("#{ENV_NAME} is malformed; falling back to the default allow-list")
    DEFAULT_OWNER_ORG_IDS
  end
end
