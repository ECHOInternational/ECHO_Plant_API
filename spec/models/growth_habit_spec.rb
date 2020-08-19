# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GrowthHabit, type: :model do
  it 'is valid with valid attributes' do
    growth_habit = build(:growth_habit)
    expect(growth_habit).to be_valid
  end
  it 'is not valid without a name' do
    growth_habit = build(:growth_habit, name: nil)
    expect(growth_habit).to_not be_valid
  end
  it 'translates the name attribute' do
    growth_habit = create(:growth_habit, name_en: 'name_en')
    growth_habit.name_es = 'name_es'
    expect(growth_habit.translations).to have_key(:en)
    expect(growth_habit.translations).to have_key(:es)
    expect(growth_habit.translations[:en]).to have_key(:name)
    expect(growth_habit.translations[:es]).to have_key(:name)
    expect(growth_habit.translations[:en][:name]).to eq('name_en')
    expect(growth_habit.translations[:es][:name]).to eq('name_es')
  end
  it 'has many plants' do
    growth_habit = create(:growth_habit)
    plant_a = create(:plant)
    plant_b = create(:plant)
    expect { growth_habit.plants << plant_a }.to change { growth_habit.plants.count }.by(1)
    expect { growth_habit.plants << plant_b }.to change { growth_habit.plants.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related growth_habits_plant records' do
      growth_habit = create(:growth_habit)
      plant = create(:plant)
      growth_habit.plants << plant
      expect { growth_habit.destroy }.to change { GrowthHabitsPlant.count }.by(-1)
    end
    it 'does not destory related plants' do
      growth_habit = create(:growth_habit)
      plant = create(:plant)
      growth_habit.plants << plant
      expect { growth_habit.destroy }.to_not change { Plant.count }
    end
  end
  it 'has many varieties' do
    growth_habit = create(:growth_habit)
    variety_a = create(:variety)
    variety_b = create(:variety)
    expect { growth_habit.varieties << variety_a }.to change { growth_habit.varieties.count }.by(1)
    expect { growth_habit.varieties << variety_b }.to change { growth_habit.varieties.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related growth_habits_variety records' do
      growth_habit = create(:growth_habit)
      variety = create(:variety)
      growth_habit.varieties << variety
      expect { growth_habit.destroy }.to change { GrowthHabitsVariety.count }.by(-1)
    end
    it 'does not destory related varieties' do
      growth_habit = create(:growth_habit)
      variety = create(:variety)
      growth_habit.varieties << variety
      expect { growth_habit.destroy }.to_not change { Variety.count }
    end
  end
end
