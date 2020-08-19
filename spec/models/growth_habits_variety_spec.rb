# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GrowthHabitsVariety, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:growth_habits_variety)
    expect(join_record).to be_valid
  end
  it 'is not valid without a variety' do
    join_record = build(:growth_habits_variety, variety: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an growth_habit' do
    join_record = build(:growth_habits_variety, growth_habit: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    variety = create(:variety)
    growth_habit = create(:growth_habit)
    expect { variety.growth_habits << growth_habit }.to_not raise_error
    expect { variety.growth_habits << growth_habit }.to raise_error
  end
end
