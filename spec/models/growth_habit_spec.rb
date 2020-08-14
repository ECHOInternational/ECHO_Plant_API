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
end
