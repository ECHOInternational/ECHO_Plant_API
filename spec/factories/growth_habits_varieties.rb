# frozen_string_literal: true

FactoryBot.define do
  factory :growth_habits_variety do
    growth_habit { build(:growth_habit) }
    variety { build(:variety) }
  end
end
