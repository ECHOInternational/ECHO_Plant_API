# frozen_string_literal: true

FactoryBot.define do
  factory :antinutrient do
    sequence(:name) { |n| "Antinutrient #{n}" }
  end
end
