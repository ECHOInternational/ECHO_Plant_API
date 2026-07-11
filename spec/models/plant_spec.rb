# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plant, type: :model do
  it 'is valid with valid attributes' do
    plant = build(:plant)
    expect(plant).to be_valid
  end
  it 'is not valid without a creator' do
    plant = build(:plant, created_by: nil)
    expect(plant).to_not be_valid
  end
  it 'is not valid without an owner' do
    plant = build(:plant, owned_by: nil)
    expect(plant).to_not be_valid
  end
  it "has a default visibility of 'private'" do
    plant = build(:plant)
    expect(plant).to be_valid
    expect(plant.visibility).to eq('private')
  end
  it 'can set visibility' do
    plant = build(:plant, :public)
    expect(plant).to be_valid
    expect(plant.visibility).to eq('public')
  end
  it 'translates the description attribute' do
    plant = create(:plant, description_en: 'description_en')
    plant.description_es = 'description_es'
    expect(plant.translations).to have_key(:en)
    expect(plant.translations).to have_key(:es)
    expect(plant.translations[:en]).to have_key(:description)
    expect(plant.translations[:es]).to have_key(:description)
    expect(plant.translations[:en][:description]).to eq('description_en')
    expect(plant.translations[:es][:description]).to eq('description_es')
  end

  it 'is versioned' do
    is_expected.to be_versioned
    plant = build(:plant)
    expect(plant).to respond_to(:versions)
  end

  it 'is destroys all related images when it is destroyed' do
    plant = create(:plant)
    create(:image, imageable: plant)
    expect { plant.destroy }.to change { Image.count }.by(-1)
  end

  describe 'range attributes' do
    let(:plant) { build(:plant) }
    describe 'nitrogen accumulation (integer)' do
      it 'has a default range of 0 to 0' do
        expect(plant.n_accumulation_range).to eq 0...1
      end
      it 'can be set to a different range' do
        plant.n_accumulation_range = 12..14
        expect { plant.save }.to_not raise_error
        expect(plant.n_accumulation_range).to include 13
        expect(plant.n_accumulation_range).to_not include 15
      end
    end
    describe 'biomass production (float)' do
      it 'has a default range of 0.0 to 0.0' do
        expect(plant.biomass_production_range).to eq 0.0..0.0
      end
      it 'can be set to a different range' do
        plant.biomass_production_range = 10..12.5
        expect { plant.save }.to_not raise_error
        expect(plant.biomass_production_range.include?(12.25)).to be true
        expect(plant.biomass_production_range.include?(9)).to be false
        expect(plant.biomass_production_range.include?(13)).to be false
      end
    end
    describe 'seasonality days range (no default)' do
      it 'has a default of nil' do
        expect(plant.seasonality_days_range).to be_nil
      end
    end
    describe 'optimal rainfall range (default 0 to infinity)' do
      it 'has a default range of 0.0 to infinity' do
        expect(plant.optimal_rainfall_range.include?(0)).to be true
        expect(plant.optimal_rainfall_range.include?(-1)).to be false
        expect(plant.optimal_rainfall_range.include?(1500)).to be true
        expect(plant.optimal_rainfall_range.include?(4.75)).to be true
      end
      it 'can be set to a different range' do
        plant.optimal_rainfall_range = 12..45
        expect { plant.save }.to_not raise_error
        expect(plant.optimal_rainfall_range.include?(12.01)).to be true
        expect(plant.optimal_rainfall_range.include?(45.04)).to be false
        expect(plant.optimal_rainfall_range.include?(11.999)).to be false
        expect(plant.optimal_rainfall_range.include?(13)).to be true
      end
    end
  end

  it 'has many antinutrients' do
    plant = create(:plant)
    antinutrient_a = create(:antinutrient, name: 'Plant Antinutrient A')
    antinutrient_b = create(:antinutrient, name: 'Plant Antinutrient B')
    expect { plant.antinutrients << antinutrient_a }.to change { plant.antinutrients.count }.by(1)
    expect { plant.antinutrients << antinutrient_b }.to change { plant.antinutrients.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related antinutrients_plants records' do
      plant = create(:plant)
      antinutrient = create(:antinutrient)
      plant.antinutrients << antinutrient
      expect { plant.destroy }.to change { AntinutrientsPlant.count }.by(-1)
    end
    it 'does not destory related antinutrients' do
      plant = create(:plant)
      antinutrient = create(:antinutrient)
      plant.antinutrients << antinutrient
      expect { plant.destroy }.to_not change { Antinutrient.count }
    end
  end
  it 'has many categories' do
    plant = create(:plant)
    category_a = create(:category, name: 'Plant Category A')
    category_b = create(:category, name: 'Plant Category B')
    expect { plant.categories << category_a }.to change { plant.categories.count }.by(1)
    expect { plant.categories << category_b }.to change { plant.categories.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related categories_plants records' do
      plant = create(:plant)
      category = create(:category)
      plant.categories << category
      expect { plant.destroy }.to change { CategoriesPlant.count }.by(-1)
    end
    it 'does not destory related categories' do
      plant = create(:plant)
      category = create(:category)
      plant.categories << category
      expect { plant.destroy }.to_not change { Category.count }
    end
  end
  it 'has many growth habits' do
    plant = create(:plant)
    growth_habit_a = create(:growth_habit, name: 'Plant Growth Habit A')
    growth_habit_b = create(:growth_habit, name: 'Plant Growth Habit B')
    expect { plant.growth_habits << growth_habit_a }.to change { plant.growth_habits.count }.by(1)
    expect { plant.growth_habits << growth_habit_b }.to change { plant.growth_habits.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related growth_habits_plants records' do
      plant = create(:plant)
      growth_habit = create(:growth_habit)
      plant.growth_habits << growth_habit
      expect { plant.destroy }.to change { GrowthHabitsPlant.count }.by(-1)
    end
    it 'does not destroy related growth habits' do
      plant = create(:plant)
      growth_habit = create(:growth_habit)
      plant.growth_habits << growth_habit
      expect { plant.destroy }.to_not change { GrowthHabit.count }
    end
  end
  it 'has many tolerances' do
    plant = create(:plant)
    tolerance_a = create(:tolerance, name: 'Plant Tolerance A')
    tolerance_b = create(:tolerance, name: 'Plant Tolerance B')
    expect { plant.tolerances << tolerance_a }.to change { plant.tolerances.count }.by(1)
    expect { plant.tolerances << tolerance_b }.to change { plant.tolerances.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related tolerances_plants records' do
      plant = create(:plant)
      tolerance = create(:tolerance)
      plant.tolerances << tolerance
      expect { plant.destroy }.to change { TolerancesPlant.count }.by(-1)
    end
    it 'does not destory related tolerances' do
      plant = create(:plant)
      tolerance = create(:tolerance)
      plant.tolerances << tolerance
      expect { plant.destroy }.to_not change { Tolerance.count }
    end
  end
  it 'has many common names' do
    plant = create(:plant)
    common_name_a = create(:common_name, name: 'Plant Common Name A', language: 'en')
    common_name_b = create(:common_name, name: 'Plant Common Name B', language: 'en')
    expect { plant.common_names << common_name_a }.to change { plant.common_names.count }.by(1)
    expect { plant.common_names << common_name_b }.to change { plant.common_names.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related common names records' do
      plant = create(:plant)
      common_name = create(:common_name)
      plant.common_names << common_name
      expect { plant.destroy }.to change { CommonName.count }.by(-1)
    end
  end
  it 'has many varieties' do
    plant = create(:plant)
    expect { create(:variety, plant: plant) }.to change { plant.varieties.count }.by(1)
    expect { create(:variety, plant: plant) }.to change { plant.varieties.count }.by(1)
    expect(plant.varieties.count).to eq 2
  end
  describe 'when it is destroyed' do
    it 'fails if there are still variety records' do
      plant = create(:plant)
      create(:variety, plant: plant)
      expect(plant.destroy).to be false
      expect(plant.destroyed?).to be false
      expect(plant.errors.count).to eq 1
    end
    it 'fails if there are still specimen records' do
      plant = create(:plant)
      create(:specimen, plant: plant)
      expect(plant.destroy).to be false
      expect(plant.destroyed?).to be false
      expect(plant.errors.count).to eq 1
    end
  end

  describe '#primary_common_name_for_locale' do
    # The fixed fallback precedence, highest priority first:
    #   1. requested language, primary == true
    #   2. 'EN', primary == true
    #   3. 'EN', any (primary true or false)
    #   4. nil
    # Within each tier, ActiveRecord's implicit ORDER BY id ASC picks the winner.
    #
    # These examples run each case twice: once with the common_names association
    # NOT loaded (the SQL path) and once with it loaded (the Ruby path), proving
    # both paths return byte-identical results.
    def resolve_both_ways(plant, locale)
      plant.reload # ensure the association is not loaded (SQL path)
      raise 'expected association to be unloaded' if plant.association(:common_names).loaded?

      sql_result = plant.primary_common_name_for_locale(locale)

      plant.common_names.load # force the association to load (Ruby path)
      raise 'expected association to be loaded' unless plant.association(:common_names).loaded?

      loaded_result = plant.primary_common_name_for_locale(locale)

      expect(loaded_result).to eq(sql_result)
      sql_result
    end

    it 'prefers the requested-language primary name (tier 1)' do
      plant = create(:plant)
      create(:common_name, plant: plant, name: 'Spanish Primary', language: 'ES', primary: true)
      create(:common_name, plant: plant, name: 'Spanish Other', language: 'ES', primary: false)
      create(:common_name, plant: plant, name: 'English Primary', language: 'EN', primary: true)

      expect(resolve_both_ways(plant, 'es')).to eq 'Spanish Primary'
    end

    it 'falls back to the EN primary name when the requested language has no primary (tier 2)' do
      plant = create(:plant)
      create(:common_name, plant: plant, name: 'Spanish Other', language: 'ES', primary: false)
      create(:common_name, plant: plant, name: 'English Primary', language: 'EN', primary: true)
      create(:common_name, plant: plant, name: 'English Other', language: 'EN', primary: false)

      expect(resolve_both_ways(plant, 'es')).to eq 'English Primary'
    end

    it 'falls back to any EN name when there is no EN primary (tier 3)' do
      plant = create(:plant)
      create(:common_name, plant: plant, name: 'Spanish Other', language: 'ES', primary: false)
      create(:common_name, plant: plant, name: 'English Other', language: 'EN', primary: false)

      expect(resolve_both_ways(plant, 'es')).to eq 'English Other'
    end

    it 'returns nil when there is no matching name (tier 4)' do
      plant = create(:plant)
      create(:common_name, plant: plant, name: 'French Only', language: 'FR', primary: false)

      expect(resolve_both_ways(plant, 'es')).to be_nil
    end

    it 'is locale-case-insensitive for the requested language' do
      plant = create(:plant)
      create(:common_name, plant: plant, name: 'Spanish Primary', language: 'ES', primary: true)

      expect(resolve_both_ways(plant, 'es')).to eq 'Spanish Primary'
      expect(resolve_both_ways(plant, 'ES')).to eq 'Spanish Primary'
    end

    it 'breaks ties within a tier by implicit id order identically on both paths' do
      # Two EN primaries (a data anomaly the SQL .first tolerates): the record
      # with the lower id wins, and both paths must agree on which one.
      plant = create(:plant)
      first = create(:common_name, plant: plant, name: 'EN Primary One', language: 'EN', primary: true)
      second = create(:common_name, plant: plant, name: 'EN Primary Two', language: 'EN', primary: true)
      winner = [first, second].min_by(&:id).name

      expect(resolve_both_ways(plant, 'en')).to eq winner
    end
  end
end
