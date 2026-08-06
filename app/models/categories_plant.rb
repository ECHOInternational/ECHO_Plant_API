# frozen_string_literal: true

# Relation table for Categories and Plants
class CategoriesPlant < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :category
  belongs_to :plant

  versioned_under_root { ['Plant', plant_id] }
end
