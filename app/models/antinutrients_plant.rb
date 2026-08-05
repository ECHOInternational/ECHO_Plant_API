# frozen_string_literal: true

# Relation table for Antinutrients and Plants
class AntinutrientsPlant < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :antinutrient
  belongs_to :plant

  versioned_under_root { ['Plant', plant_id] }
end
