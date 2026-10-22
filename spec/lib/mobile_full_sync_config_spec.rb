# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobileFullSyncConfig do
  let(:default) { described_class::DEFAULT_OWNER_ORG_IDS }
  let(:org_a) { '0b6f7c1e-2a39-4c5e-9d0e-1f2a3b4c5d6e' }
  let(:org_b) { 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d' }

  describe '.parse' do
    it 'defaults to the production ECHO organization when unset' do
      expect(described_class.parse(nil)).to eq(default)
      expect(default).to eq(['99ee034e-6a85-44fc-a366-cb6dbc637783'])
    end

    it 'defaults when blank' do
      expect(described_class.parse("  \n")).to eq(default)
    end

    it 'reads one id' do
      expect(described_class.parse(org_a)).to eq([org_a])
    end

    it 'reads a comma-separated list, trimming whitespace, downcasing and de-duplicating' do
      expect(described_class.parse(" #{org_a.upcase} , #{org_b},#{org_a} ")).to eq([org_a, org_b])
    end

    it 'fails closed to the default when any entry is malformed' do
      expect(described_class.parse("#{org_a},not-a-uuid")).to eq(default)
      expect(described_class.parse("#{org_a},,#{org_b}")).to eq(default)
    end

    it 'logs a warning when it falls back on a malformed value' do
      logger = instance_double(Logger, warn: nil)
      described_class.parse('nope', logger: logger)
      expect(logger).to have_received(:warn).with(/MOBILE_FULL_SYNC_OWNER_ORG_IDS/)
    end

    it 'returns a frozen list' do
      expect(described_class.parse(org_a)).to be_frozen
    end
  end

  it 'is wired into the application configuration at boot' do
    expect(Rails.configuration.x.mobile_full_sync_owner_org_ids).to eq(
      described_class.parse(ENV.fetch('MOBILE_FULL_SYNC_OWNER_ORG_IDS', nil))
    )
    expect(MobileFullSyncGuard.owner_organization_ids).to eq(Rails.configuration.x.mobile_full_sync_owner_org_ids)
  end
end
