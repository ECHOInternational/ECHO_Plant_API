# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    uid { Faker::Internet.uuid }
    trust_levels { { 'plant' => 4 } }
    initialize_with { new(attributes.stringify_keys) }

    # Every real request resolves a principal and a personal organization in
    # ApplicationController#resolve_actor before any policy or mutation runs;
    # the only way they are nil in production is a database failure, which the
    # controller deliberately degrades to legacy authz. A built user without
    # them therefore models a failure mode, not the normal case -- and create
    # mutations now refuse to write unattributable rows, so specs that build a
    # bare user were exercising that failure path by accident.
    #
    # Use the :unresolved trait to model the failure deliberately.
    after(:build) do |user|
      next if user.instance_variable_get(:@skip_principal)

      principal = Principal.resolve!(issuer: 'spec', external_uid: user.id, email: user.email)
      user.principal = principal
      user.personal_organization = Organization.personal_for!(principal)
    end

    # A request whose identity could not be resolved (resolve_actor degraded).
    trait :unresolved do
      after(:build) do |user|
        user.principal = nil
        user.personal_organization = nil
      end
    end
    trait :readonly do
      trust_levels { { 'plant' => 1 } }
    end
    trait :readwrite do
      trust_levels { { 'plant' => 2 } }
    end
    trait :admin do
      trust_levels { { 'plant' => 9 } }
    end
    trait :superadmin do
      trust_levels { { 'plant' => 10 } }
    end
  end
end
