# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RelationSets::CommonNames do
  let(:plant) { create(:plant) }

  describe '.parse' do
    it 'normalises, de-duplicates case-insensitively within a language, and sorts' do
      parsed = described_class.parse([['und', ' Bhindi ', false], ['EN', 'Okra', true], ['EN', "Lady's finger", false],
                                      ['EN', 'okra', false], ['UND', 'bhindi', false]])
      expect(parsed).to eq([['EN', "Lady's finger", false], ['EN', 'Okra', true], ['UND', 'Bhindi', false]])
    end

    it 'sorts names bytewise and keeps the first spelling of a case-insensitive duplicate' do
      parsed = described_class.parse([['EN', 'B', true], ['EN', 'b', false], ['EN', 'a', false]])
      expect(parsed.map { |e| e[1] }).to eq(%w[B a]) # 'B' (0x42) sorts before 'a' (0x61); 'b' duplicates 'B'
      expect(parsed.first).to eq(['EN', 'B', true])
    end

    it 'accepts the canonical string' do
      expect(described_class.parse('[["EN","Okra",true]]')).to eq([['EN', 'Okra', true]])
      expect(described_class.parse('[]')).to eq([])
    end

    it 'refuses malformed entries' do
      expect { described_class.parse('{}') }.to raise_error(ArgumentError, /must be an array/)
      expect { described_class.parse([['EN', '', true]]) }.to raise_error(ArgumentError, /blank/)
      expect { described_class.parse([%w[EN Okra yes]]) }.to raise_error(ArgumentError)
      expect { described_class.parse([['ES', 'Quimbombo', true]]) }.to raise_error(ArgumentError, /not managed/)
    end
  end

  describe '.validate' do
    it 'allows one primary per language and refuses two' do
      expect(described_class.validate(plant, [['EN', 'A', true], ['UND', 'B', false]])).to eq([])
      expect(described_class.validate(plant, [['EN', 'A', true], ['EN', 'B', true]]).first).to match(/2 primary names in EN/)
    end
  end

  describe '.apply' do
    it 'creates missing rows, destroys extra managed rows, and leaves other languages alone' do
      CommonName.create!(plant: plant, name: 'Old', language: 'EN', primary: true)
      CommonName.create!(plant: plant, name: 'Gombo', language: 'FR', primary: true)
      described_class.apply(plant, described_class.parse([['EN', 'Okra', true], ['UND', 'Bhindi', false]]))
      rows = CommonName.where(plant: plant).pluck(:language, :name, :primary)
      expect(rows).to contain_exactly(['EN', 'Okra', true], ['UND', 'Bhindi', false], ['FR', 'Gombo', true])
    end

    it 'adopts incoming casing and the primary flag on matched rows and keeps their location' do
      row = CommonName.create!(plant: plant, name: 'okra', language: 'EN', primary: false, location: 'Kenya')
      CommonName.create!(plant: plant, name: 'Gumbo', language: 'EN', primary: true)
      described_class.apply(plant, described_class.parse([['EN', 'Okra', true], ['EN', 'Gumbo', false]]))
      row.reload
      expect([row.name, row.primary, row.location]).to eq(['Okra', true, 'Kenya'])
      expect(CommonName.find_by(plant: plant, name: 'Gumbo').primary).to be(false)
    end

    it 'writes nothing when the sets already match' do
      CommonName.create!(plant: plant, name: 'Okra', language: 'EN', primary: true)
      expect do
        described_class.apply(plant, described_class.parse(described_class.read(plant)))
      end.not_to change { PaperTrail::Version.count }
    end
  end
end
