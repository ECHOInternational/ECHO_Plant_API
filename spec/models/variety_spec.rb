# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Variety, type: :model do
  it 'is valid with valid attributes' do
    variety = build(:variety)
    expect(variety).to be_valid
  end
  it 'is not valid without a name' do
    variety = build(:variety, name: nil)
    expect(variety).to_not be_valid
  end
  it 'is not valid without a creator' do
    variety = build(:variety, created_by: nil)
    expect(variety).to_not be_valid
  end
  it 'is not valid without an owner' do
    variety = build(:variety, owned_by: nil)
    expect(variety).to_not be_valid
  end
  it "has a default visibility of 'private'" do
    variety = build(:variety)
    expect(variety).to be_valid
    expect(variety.visibility).to eq('private')
  end
  it 'can set visibility' do
    variety = build(:variety, :public)
    expect(variety).to be_valid
    expect(variety.visibility).to eq('public')
  end
  it 'translates the name attribute' do
    variety = create(:variety, name_en: 'name_en')
    variety.name_es = 'name_es'
    expect(variety.translations).to have_key(:en)
    expect(variety.translations).to have_key(:es)
    expect(variety.translations[:en]).to have_key(:name)
    expect(variety.translations[:es]).to have_key(:name)
    expect(variety.translations[:en][:name]).to eq('name_en')
    expect(variety.translations[:es][:name]).to eq('name_es')
  end

  it 'translates the description attribute' do
    variety = create(:variety, description_en: 'description_en')
    variety.description_es = 'description_es'
    expect(variety.translations).to have_key(:en)
    expect(variety.translations).to have_key(:es)
    expect(variety.translations[:en]).to have_key(:description)
    expect(variety.translations[:es]).to have_key(:description)
    expect(variety.translations[:en][:description]).to eq('description_en')
    expect(variety.translations[:es][:description]).to eq('description_es')
  end

  it 'is destroys all related images when it is destroyed' do
    variety = create(:variety)
    create(:image, imageable: variety)
    expect { variety.destroy }.to change { Image.count }.by(-1)
  end

  it 'is versioned' do
    is_expected.to be_versioned
    variety = build(:variety)
    expect(variety).to respond_to(:versions)
  end

  it 'belongs to a plant' do
    plant = create(:plant)
    variety = create(:variety, plant: plant)
    expect(variety.plant_id).to eq plant.id
  end

  describe 'when it is destroyed' do
    it 'does not destroy related plants' do
      plant = create(:plant)
      variety = create(:variety, plant: plant)
      expect { variety.destroy }.to_not change { Plant.count }
    end
  end

  describe 'range attributes' do
    let(:variety) { build(:variety) }
    describe 'nitrogen accumulation (integer)' do
      it 'has a default range of 0 to 0' do
        expect(variety.n_accumulation_range).to eq 0...1
      end
      it 'can be set to a different range' do
        variety.n_accumulation_range = 12..14
        expect { variety.save }.to_not raise_error
        expect(variety.n_accumulation_range).to include 13
        expect(variety.n_accumulation_range).to_not include 15
      end
    end
    describe 'biomass production (float)' do
      it 'has a default range of 0.0 to 0.0' do
        expect(variety.biomass_production_range).to eq 0.0..0.0
      end
      it 'can be set to a different range' do
        variety.biomass_production_range = 10..12.5
        expect { variety.save }.to_not raise_error
        expect(variety.biomass_production_range.include?(12.25)).to be true
        expect(variety.biomass_production_range.include?(9)).to be false
        expect(variety.biomass_production_range.include?(13)).to be false
      end
    end
    describe 'seasonality days range (no default)' do
      it 'has a default of nil' do
        expect(variety.seasonality_days_range).to be_nil
      end
    end
    describe 'optimal rainfall range (default 0 to infinity)' do
      it 'has a default range of 0.0 to infinity' do
        expect(variety.optimal_rainfall_range.include?(0)).to be true
        expect(variety.optimal_rainfall_range.include?(-1)).to be false
        expect(variety.optimal_rainfall_range.include?(1500)).to be true
        expect(variety.optimal_rainfall_range.include?(4.75)).to be true
      end
      it 'can be set to a different range' do
        variety.optimal_rainfall_range = 12..45
        expect { variety.save }.to_not raise_error
        expect(variety.optimal_rainfall_range.include?(12.01)).to be true
        expect(variety.optimal_rainfall_range.include?(45.04)).to be false
        expect(variety.optimal_rainfall_range.include?(11.999)).to be false
        expect(variety.optimal_rainfall_range.include?(13)).to be true
      end
    end
  end

  it 'has many antinutrients' do
    variety = create(:variety)
    antinutrient_a = create(:antinutrient, name: 'Variety Antinutrient A')
    antinutrient_b = create(:antinutrient, name: 'Variety Antinutrient B')
    expect { variety.antinutrients << antinutrient_a }.to change { variety.antinutrients.count }.by(1)
    expect { variety.antinutrients << antinutrient_b }.to change { variety.antinutrients.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related antinutrients_varieties records' do
      variety = create(:variety)
      antinutrient = create(:antinutrient)
      variety.antinutrients << antinutrient
      expect { variety.destroy }.to change { AntinutrientsVariety.count }.by(-1)
    end
    it 'does not destroy related antinutrients' do
      variety = create(:variety)
      antinutrient = create(:antinutrient)
      variety.antinutrients << antinutrient
      expect { variety.destroy }.to_not change { Antinutrient.count }
    end
  end
  it 'has many growth habits' do
    variety = create(:variety)
    growth_habit_a = create(:growth_habit, name: 'Variety Growth Habit A')
    growth_habit_b = create(:growth_habit, name: 'Variety Growth Habit B')
    expect { variety.growth_habits << growth_habit_a }.to change { variety.growth_habits.count }.by(1)
    expect { variety.growth_habits << growth_habit_b }.to change { variety.growth_habits.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related growth_habits_varieties records' do
      variety = create(:variety)
      growth_habit = create(:growth_habit)
      variety.growth_habits << growth_habit
      expect { variety.destroy }.to change { GrowthHabitsVariety.count }.by(-1)
    end
    it 'does not destroy related growth habits' do
      variety = create(:variety)
      growth_habit = create(:growth_habit)
      variety.growth_habits << growth_habit
      expect { variety.destroy }.to_not change { GrowthHabit.count }
    end
  end
  it 'has many tolerances' do
    variety = create(:variety)
    tolerance_a = create(:tolerance, name: 'Variety Tolerance A')
    tolerance_b = create(:tolerance, name: 'Variety Tolerance B')
    expect { variety.tolerances << tolerance_a }.to change { variety.tolerances.count }.by(1)
    expect { variety.tolerances << tolerance_b }.to change { variety.tolerances.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related tolerances_varieties records' do
      variety = create(:variety)
      tolerance = create(:tolerance)
      variety.tolerances << tolerance
      expect { variety.destroy }.to change { TolerancesVariety.count }.by(-1)
    end
    it 'does not destory related tolerances' do
      variety = create(:variety)
      tolerance = create(:tolerance)
      variety.tolerances << tolerance
      expect { variety.destroy }.to_not change { Tolerance.count }
    end
  end
end
