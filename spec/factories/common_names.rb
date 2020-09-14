# frozen_string_literal: true

FactoryBot.define do
  factory :common_name do
    sequence(:name) { |n| "Common Name #{n}" }
    language { Faker::Address.country_code }
    location { Faker::Address.country }
    plant { build(:plant) }
    primary { false }
  end
end
