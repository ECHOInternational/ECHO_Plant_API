# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GrowthHabitsPlant, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:growth_habits_plant)
    expect(join_record).to be_valid
  end
  it 'is not valid without a plant' do
    join_record = build(:growth_habits_plant, plant: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an growth_habit' do
    join_record = build(:growth_habits_plant, growth_habit: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    plant = create(:plant)
    growth_habit = create(:growth_habit)
    expect { plant.growth_habits << growth_habit }.to_not raise_error
    expect { plant.growth_habits << growth_habit }.to raise_error
  end
end
