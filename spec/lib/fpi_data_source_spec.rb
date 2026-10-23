# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_data_source')

# fpi:bootstrap mirrors FPI's organization by this id, so it must be the id the
# IdP uses in each environment (one organization, one id in both systems).
RSpec.describe FpiDataSource do
  describe '.organization_id' do
    it 'is the production id in production, development and test' do
      %w[production development test].each do |env|
        expect(described_class.organization_id(env: env, override: nil)).to eq('b7ab3117-e610-4b7d-b097-a51ebe911d79')
      end
    end

    it 'is ECHOcommunity staging\'s food-plants-international on staging' do
      expect(described_class.organization_id(env: 'staging', override: nil)).to eq('ad8f2875-2bd5-46fb-b514-9f6becf47ad4')
    end

    it 'lets FPI_ORG_ID override the default' do
      expect(described_class.organization_id(env: 'staging', override: '11111111-2222-4333-8444-555555555555'))
        .to eq('11111111-2222-4333-8444-555555555555')
    end
  end
end
