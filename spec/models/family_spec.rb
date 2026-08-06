# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, type: :model do
  describe 'creation' do
    it 'is refused outside an importing block' do
      expect { create(:family) }.to raise_error(Family::ImmutableListError)
    end

    it 'is allowed inside an importing block' do
      family = described_class.importing { create(:family, name: 'Fabaceae') }
      expect(family).to be_persisted
      expect(family.name).to eq('Fabaceae')
    end
  end

  describe 'destruction' do
    it 'is refused outside an importing block' do
      family = described_class.importing { create(:family) }
      expect { family.destroy }.to raise_error(Family::ImmutableListError)
    end
  end

  describe 'metadata updates' do
    let(:family) { described_class.importing { create(:family, name: 'Fabaceae') } }

    it 'are allowed outside an importing block' do
      expect(family.update(seed_banking_rank: 5)).to be true
    end

    it 'translate the description' do
      Mobility.with_locale(:en) { family.description = 'Pea family' }
      Mobility.with_locale(:es) { family.description = 'Familia de los guisantes' }
      family.save!
      expect(family.translations['en']['description']).to eq('Pea family')
      expect(family.translations['es']['description']).to eq('Familia de los guisantes')
    end
  end

  describe 'validations' do
    subject(:family) { described_class.new(valid_attributes) }

    let(:valid_attributes) do
      { name: 'Fabaceae', kingdom: 'Plantae', classification_source: 'catalogue-of-life',
        classification_version: 'COL26.7 XR', snapshot_date: Date.new(2026, 7, 17) }
    end

    it { is_expected.to be_valid }

    it 'requires a name' do
      family.name = nil
      expect(family).not_to be_valid
    end

    it 'rejects a seed banking rank outside 1..5' do
      family.seed_banking_rank = 6
      expect(family).not_to be_valid
    end

    it 'rejects a duplicate name case-insensitively' do
      described_class.importing { described_class.create!(valid_attributes) }
      duplicate = described_class.new(valid_attributes.merge(name: 'fabaceae'))
      expect do
        described_class.importing { duplicate.save! }
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'scopes' do
    it 'separates accepted from superseded' do
      accepted, superseded = described_class.importing do
        [create(:family, name: 'Malvaceae'),
         create(:family, name: 'Tiliaceae', status: 'superseded')]
      end
      expect(described_class.accepted).to include(accepted)
      expect(described_class.accepted).not_to include(superseded)
      expect(described_class.superseded).to contain_exactly(superseded)
    end
  end

  describe '#translations_array' do
    it 'flattens the Mobility container into per-locale rows' do
      family = described_class.importing { create(:family) }
      Mobility.with_locale(:en) do
        family.description = 'Pea family'
        family.seed_banking_notes = 'Highly suitable'
      end
      family.save!

      row = family.translations_array.find { |t| t[:locale] == 'en' }
      expect(row[:description]).to eq('Pea family')
      expect(row[:seed_banking_notes]).to eq('Highly suitable')
    end
  end

  describe 'the database trigger' do
    it 'refuses a raw INSERT that bypasses the model' do
      expect do
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO families (name, kingdom, classification_source,
                                classification_version, snapshot_date,
                                created_at, updated_at)
          VALUES ('Sneakaceae', 'Plantae', 'manual', 'none', '2026-01-01',
                  now(), now())
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end

    it 'refuses a raw DELETE that bypasses the model' do
      family = described_class.importing { create(:family) }
      expect do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(['DELETE FROM families WHERE id = ?', family.id])
        )
      end.to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end

    # Guards the reset in Family.importing's ensure block. A transaction-local
    # setting outlives the block it was set in, so without an explicit reset
    # the list would stay unlocked for the rest of the example and every
    # trigger assertion above would pass without proving anything.
    it 're-locks the list as soon as an importing block exits' do
      described_class.importing { create(:family, name: 'Firstaceae') }

      expect { create(:family, name: 'Secondaceae') }
        .to raise_error(described_class::ImmutableListError)

      expect do
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO families (name, kingdom, classification_source,
                                classification_version, snapshot_date,
                                created_at, updated_at)
          VALUES ('Thirdaceae', 'Plantae', 'manual', 'none', '2026-01-01',
                  now(), now())
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end
  end
end
