# frozen_string_literal: true

FactoryBot.define do
  factory :tolerances_plant do
    tolerance { build(:tolerance) }
    plant { build(:plant) }
  end
end
