# frozen_string_literal: true

FactoryBot.define do
  factory :tolerance do
    sequence(:name) { |n| "Tolerance #{n}" }
  end
end
