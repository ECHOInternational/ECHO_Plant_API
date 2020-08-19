# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Antinutrient, type: :model do
  it 'is valid with valid attributes' do
    antinutrient = build(:antinutrient)
    expect(antinutrient).to be_valid
  end
  it 'is not valid without a name' do
    antinutrient = build(:antinutrient, name: nil)
    expect(antinutrient).to_not be_valid
  end
  it 'translates the name attribute' do
    antinutrient = create(:antinutrient, name_en: 'name_en')
    antinutrient.name_es = 'name_es'
    expect(antinutrient.translations).to have_key(:en)
    expect(antinutrient.translations).to have_key(:es)
    expect(antinutrient.translations[:en]).to have_key(:name)
    expect(antinutrient.translations[:es]).to have_key(:name)
    expect(antinutrient.translations[:en][:name]).to eq('name_en')
    expect(antinutrient.translations[:es][:name]).to eq('name_es')
  end

  it 'has many plants' do
    antinutrient = create(:antinutrient)
    plant_a = create(:plant)
    plant_b = create(:plant)
    expect { antinutrient.plants << plant_a }.to change { antinutrient.plants.count }.by(1)
    expect { antinutrient.plants << plant_b }.to change { antinutrient.plants.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related antinutrients_plant records' do
      antinutrient = create(:antinutrient)
      plant = create(:plant)
      antinutrient.plants << plant
      expect { antinutrient.destroy }.to change { AntinutrientsPlant.count }.by(-1)
    end
    it 'does not destory related plants' do
      antinutrient = create(:antinutrient)
      plant = create(:plant)
      antinutrient.plants << plant
      expect { antinutrient.destroy }.to_not change { Plant.count }
    end
  end
  it 'has many varieties' do
    antinutrient = create(:antinutrient)
    variety_a = create(:variety)
    variety_b = create(:variety)
    expect { antinutrient.varieties << variety_a }.to change { antinutrient.varieties.count }.by(1)
    expect { antinutrient.varieties << variety_b }.to change { antinutrient.varieties.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related antinutrients_variety records' do
      antinutrient = create(:antinutrient)
      variety = create(:variety)
      antinutrient.varieties << variety
      expect { antinutrient.destroy }.to change { AntinutrientsVariety.count }.by(-1)
    end
    it 'does not destory related varieties' do
      antinutrient = create(:antinutrient)
      variety = create(:variety)
      antinutrient.varieties << variety
      expect { antinutrient.destroy }.to_not change { Variety.count }
    end
  end
end
