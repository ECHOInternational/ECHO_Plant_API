# frozen_string_literal: true

FactoryBot.define do
  factory :antinutrients_variety do
    antinutrient { build(:antinutrient) }
    variety { build(:variety) }
  end
end
