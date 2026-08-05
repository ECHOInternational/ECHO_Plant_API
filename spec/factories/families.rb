# frozen_string_literal: true

# Deliberately does NOT stamp ownership. Family is reference data with no
# owner, unlike the five owned models covered by spec/support/factory_ownership.
FactoryBot.define do
  factory :family do
    sequence(:name) { |n| "Testaceae#{n}" }
    kingdom { 'Plantae' }
    plant_type { 'Angiosperms' }
    status { 'accepted' }
    classification_source { 'catalogue-of-life' }
    classification_version { 'COL26.7 XR' }
    snapshot_date { Date.new(2026, 7, 17) }
  end
end
