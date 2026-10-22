# frozen_string_literal: true

require_relative '../../lib/mobile_full_sync_config'

# Allow-list for the mobile full-sync guard (MobileFullSyncGuard). Read once
# at boot. The default depends on RAILS_ENV (see MobileFullSyncConfig); the
# MOBILE_FULL_SYNC_OWNER_ORG_IDS variable overrides it.
Rails.application.config.x.mobile_full_sync_owner_org_ids =
  MobileFullSyncConfig.parse(ENV.fetch(MobileFullSyncConfig::ENV_NAME, nil), env: Rails.env, logger: Rails.logger)
