# frozen_string_literal: true

FactoryBot.define do
  factory :specimen do
    sequence(:name) { |n| "Specimen #{n}" }
    plant { build(:plant) }
    variety { build(:variety) }
    terminated { false }
    created_by { Faker::Internet.email }
    owned_by { Faker::Internet.email }
    successful { nil }
    recommended { nil }
    saved_seed { nil }
    will_share_seed { nil }
    will_plant_again { nil }
    notes { nil }

    trait :public do
      visibility { :public }
    end
    trait :draft do
      visibility { :draft }
    end
    trait :deleted do
      visibility { :deleted }
    end
    trait :private do
      visibility { :private }
    end
  end
end
