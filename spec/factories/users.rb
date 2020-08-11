# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    uid { Faker::Internet.uuid }
    trust_levels { { 'plant' => 4 } }
    initialize_with { new(attributes.stringify_keys) }
    trait :readonly do
      trust_levels { { 'plant' => 1 } }
    end
    trait :readwrite do
      trust_levels { { 'plant' => 2 } }
    end
    trait :admin do
      trust_levels { { 'plant' => 8 } }
    end
    trait :superadmin do
      trust_levels { { 'plant' => 9 } }
    end
  end
end
