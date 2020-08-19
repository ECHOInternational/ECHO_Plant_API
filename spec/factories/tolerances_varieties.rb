# frozen_string_literal: true

FactoryBot.define do
  factory :tolerances_variety do
    tolerance { build(:tolerance) }
    variety { build(:variety) }
  end
end
