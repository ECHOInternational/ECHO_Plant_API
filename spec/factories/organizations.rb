# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }

    # Default to personal kind; callers must provide a principal or use a trait.
    kind { "personal" }

    trait :personal do
      kind            { "personal" }
      external_idp_id { nil }
      # strategy: :create ensures principal has a saved id even when the org
      # is only built (not saved), satisfying the principal_id presence check.
      association     :principal, strategy: :create
    end

    trait :real do
      kind            { "real" }
      external_idp_id { Faker::Internet.uuid }
      # No principal for real orgs.
    end
  end
end
