# frozen_string_literal: true

FactoryBot.define do
  factory :variety do
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

    sequence(:name) { |n| "Variety #{n}" }
    has_edible_green_leaves { false }
    has_edible_immature_fruit { false }
    has_edible_mature_fruit { false }
    can_be_used_for_fodder { false }
    description { '<h1>Lorem ipsum dolor sit amet, consectetur adipisicing elit.</h1><p>Velit, libero nulla! Magni amet, reiciendis iste. Placeat eligendi magni recusandae aspernatur suscipit, rem maxime impedit velit, nam, consequuntur commodi! Hic, repellendus.</p>' }
    created_by { Faker::Internet.email }
    owned_by { Faker::Internet.email }
    plant { create(:plant) }

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
