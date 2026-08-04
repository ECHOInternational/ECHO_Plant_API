# frozen_string_literal: true

FactoryBot.define do
  factory :specimen do
    # Ownership as the S3 backfill left it in production; see
    # spec/support/factory_ownership.rb. Pass owner_organization_id explicitly
    # to override, or the :unowned trait to model a pre-backfill row.
    transient do
      unowned { false }
    end

    after(:build) do |record, evaluator|
      FactoryOwnership.stamp!(record) unless evaluator.unowned
    end

    # The pre-backfill state: ownership columns NULL and no principal or
    # personal organization brought into existence as a side effect. Real for
    # exactly one audience -- OwnershipBackfill's own specs, which must start
    # from the world the backfill was written to repair.
    trait :unowned do
      unowned { true }
    end

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
