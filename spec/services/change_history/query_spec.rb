# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::Query do
  describe '#relation', versioning: true do
    it "returns the record's own versions newest first" do
      plant = create(:plant, scientific_name: 'One')
      plant.update!(scientific_name: 'Two')

      ids = described_class.new(plant).relation.pluck(:id)
      expect(ids).to eq ids.sort.reverse
      expect(ids.size).to eq 2
    end

    it 'includes child versions stamped with this root' do
      plant = create(:plant)
      common_name = create(:common_name, plant: plant)

      relation = described_class.new(plant).relation
      expect(relation.where(item_type: 'CommonName', item_id: common_name.id)).to exist
    end

    it 'excludes another record history' do
      plant = create(:plant)
      other = create(:plant)
      create(:common_name, plant: other)

      item_ids = described_class.new(plant).relation.pluck(:item_id)
      expect(item_ids).to all(eq(plant.id))
    end

    it 'excludes touch versions that recorded no changes' do
      plant = create(:plant)
      before_count = described_class.new(plant).relation.count
      plant.touch

      expect(described_class.new(plant).relation.count).to eq before_count
    end

    it 'works for a variety root' do
      variety = create(:variety)
      variety.update!(has_edible_green_leaves: true)

      expect(described_class.new(variety).relation.count).to eq 2
    end
  end

  describe '.newest_version_id', versioning: true do
    it 'returns the highest version id for the item' do
      plant = create(:plant, scientific_name: 'One')
      plant.update!(scientific_name: 'Two')

      expected = PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).maximum(:id)
      expect(described_class.newest_version_id('Plant', plant.id)).to eq expected
    end

    it 'returns nil when the item has no versions' do
      expect(described_class.newest_version_id('Plant', SecureRandom.uuid)).to be_nil
    end
  end
end
