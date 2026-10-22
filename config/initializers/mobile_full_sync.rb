# frozen_string_literal: true

require_relative '../../lib/mobile_full_sync_config'

# Allow-list for the mobile full-sync guard (MobileFullSyncGuard). Read once
# at boot; changing it needs a new task definition, like every other env var.
Rails.application.config.x.mobile_full_sync_owner_org_ids =
  MobileFullSyncConfig.parse(ENV.fetch(MobileFullSyncConfig::ENV_NAME, nil), logger: Rails.logger)
