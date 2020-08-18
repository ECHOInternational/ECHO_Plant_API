# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tolerance, type: :model do
  it 'is valid with valid attributes' do
    tolerance = build(:tolerance)
    expect(tolerance).to be_valid
  end
  it 'is not valid without a name' do
    tolerance = build(:tolerance, name: nil)
    expect(tolerance).to_not be_valid
  end
  it 'translates the name attribute' do
    tolerance = create(:tolerance, name_en: 'name_en')
    tolerance.name_es = 'name_es'
    expect(tolerance.translations).to have_key(:en)
    expect(tolerance.translations).to have_key(:es)
    expect(tolerance.translations[:en]).to have_key(:name)
    expect(tolerance.translations[:es]).to have_key(:name)
    expect(tolerance.translations[:en][:name]).to eq('name_en')
    expect(tolerance.translations[:es][:name]).to eq('name_es')
  end

  it 'has many plants' do
    tolerance = create(:tolerance)
    plant_a = create(:plant)
    plant_b = create(:plant)
    expect { tolerance.plants << plant_a }.to change { tolerance.plants.count }.by(1)
    expect { tolerance.plants << plant_b }.to change { tolerance.plants.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related tolerances_plant records' do
      tolerance = create(:tolerance)
      plant = create(:plant)
      tolerance.plants << plant
      expect { tolerance.destroy }.to change { TolerancesPlant.count }.by(-1)
    end
    it 'does not destroy related plants' do
      tolerance = create(:tolerance)
      plant = create(:plant)
      tolerance.plants << plant
      expect { tolerance.destroy }.to_not change { Plant.count }
    end
  end
end
