# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommonName, type: :model do
  it 'is valid with valid attributes' do
    common_name = build(:common_name)
    expect(common_name).to be_valid
  end
  it 'is not valid without a name' do
    common_name = build(:common_name, name: nil)
    expect(common_name).to_not be_valid
  end
  it 'is not valid without a language' do
    common_name = build(:common_name, language: nil)
    expect(common_name).to_not be_valid
  end
  it 'is not valid without an plant' do
    common_name = build(:common_name, plant: nil)
    expect(common_name).to_not be_valid
  end
  it 'is versioned' do
    is_expected.to be_versioned
    common_name = build(:common_name)
    expect(common_name).to respond_to(:versions)
  end

  it 'belongs to a plant' do
    plant = create(:plant)
    common_name = create(:common_name, plant: plant)
    expect(common_name.plant).to eq plant
  end

  describe 'when it is destroyed' do
    it 'does not destory related plants' do
      plant = create(:plant)
      common_name = create(:common_name, plant: plant)
      expect { common_name.destroy }.to_not change { Plant.count }
    end
  end
end
