# frozen_string_literal: true

FactoryBot.define do
  factory :principal do
    identity_issuer { 'https://www.echocommunity.org' }
    external_uid    { Faker::Internet.uuid }
    email           { Faker::Internet.email }
    display_name    { Faker::Name.name }
    kind            { 'human' }

    trait :service do
      external_uid { nil }
      kind         { 'service' }
      email        { 'service@plant-api.internal' }
      identity_issuer { 'plant-api' }
    end

    trait :legacy do
      external_uid    { nil }
      identity_issuer { 'legacy-email' }
    end
  end
end
