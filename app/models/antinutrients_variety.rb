# frozen_string_literal: true

# Relation table for Antinutrients and Varieties
class AntinutrientsVariety < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :antinutrient
  belongs_to :variety

  versioned_under_root { ['Variety', variety_id] }
end
