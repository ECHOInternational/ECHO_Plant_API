# frozen_string_literal: true

FactoryBot.define do
  factory :record_draft do
    association :draftable, factory: :plant
    data { {} }
    base_updated_at { Time.current }
    author_principal_id { create(:principal).id }
    last_editor_principal_id { author_principal_id }
  end
end
