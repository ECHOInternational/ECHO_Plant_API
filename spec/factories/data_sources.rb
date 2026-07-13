# frozen_string_literal: true

FactoryBot.define do
  factory :data_source do
    name              { Faker::Company.name }
    source_system_key { Faker::Internet.slug }
    association :organization, factory: %i[organization real]
    notes { nil }
  end
end
