# frozen_string_literal: true

FactoryBot.define do
  factory :life_cycle_event do
    # Required for all
    specimen { build(:specimen) }
    datetime { DateTime.now }
    # Optional for all
    notes { Faker::Lorem.paragraph }
    # Additional Fields
    location { build(:location) }
    quantity { rand(1000) }
    quality { rand(10) }
    percent { rand(100) }
    source { 'Source' }
    sequence(:accession) { |n| "Accession #{n}" }
    condition { 'good' }
    unit { 'weight' }
    between_row_spacing { rand(100) }
    in_row_spacing { rand(100) }
    soil_preparation { 'full_till' }
  end
end
