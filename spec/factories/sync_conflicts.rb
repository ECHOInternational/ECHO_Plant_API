# frozen_string_literal: true

FactoryBot.define do
  factory :sync_conflict do
    association :syncable, factory: :plant
    association :data_source
    conflict_type { 'content' }
    status        { 'open' }
    base_payload     { {} }
    local_payload    { {} }
    incoming_payload { {} }
    metadata         { {} }

    trait :source_deletion do
      conflict_type { 'source_deletion' }
    end

    trait :resolved do
      status     { 'resolved' }
      resolution { 'accepted_local' }
    end

    trait :dismissed do
      status { 'dismissed' }
    end
  end
end
