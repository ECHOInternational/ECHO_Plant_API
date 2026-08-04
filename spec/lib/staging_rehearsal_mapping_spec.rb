# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/staging_rehearsal_mapping')

# This module fabricates identities. The only thing keeping that out of
# production is the database guard, so the guard gets tested first and hardest.
RSpec.describe StagingRehearsalMapping do
  describe '.guard_staging!' do
    it 'refuses any database that is not the staging one' do
      expect { described_class.guard_staging! }
        .to raise_error(/REFUSING.*Plant_API_staging/m)
    end

    it 'names the database it actually found, so a misfire is diagnosable' do
      expect { described_class.guard_staging! }.to raise_error(/#{Regexp.escape(ActiveRecord::Base.connection.current_database)}/)
    end

    it 'allows the staging database' do
      allow(ActiveRecord::Base.connection).to receive(:current_database).and_return('Plant_API_staging')
      expect { described_class.guard_staging! }.not_to raise_error
    end
  end

  describe '.write!' do
    it 'refuses to write anything outside staging' do
      expect { described_class.write! }.to raise_error(/REFUSING/)
    end
  end

  describe '.user_entry' do
    it 'is deterministic, so a re-run reuses the identity instead of minting a second' do
      expect(described_class.user_entry('a@b.com')).to eq(described_class.user_entry('a@b.com'))
    end

    it 'gives different emails different uids' do
      expect(described_class.user_entry('a@b.com')['uid'])
        .not_to eq described_class.user_entry('c@d.com')['uid']
    end

    it 'produces a uid postgres will accept as a uuid' do
      uid = described_class.user_entry('a@b.com')['uid']
      expect(uid).to match(/\A\h{8}-\h{4}-4\h{3}-8\h{3}-\h{12}\z/)
      expect { Principal.create!(identity_issuer: 'spec', external_uid: uid, email: 'a@b.com', kind: 'human') }
        .not_to raise_error
    end
  end

  describe '.owner_emails' do
    it 'excludes the shared address so the backfill still routes it to a service principal' do
      allow(ActiveRecord::Base.connection).to receive(:select_values).and_return(
        ['echo@echonet.org', 'someone@example.com']
      )
      expect(described_class.owner_emails).to eq ['someone@example.com']
    end
  end
end
