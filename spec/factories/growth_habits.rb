# frozen_string_literal: true

FactoryBot.define do
  factory :growth_habit do
    sequence(:name) { |n| "Growth Habit #{n}" }
  end
end
