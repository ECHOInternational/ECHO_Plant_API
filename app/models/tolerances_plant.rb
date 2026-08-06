# frozen_string_literal: true

# Relation table for Tolerances and Plants
class TolerancesPlant < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :tolerance
  belongs_to :plant

  versioned_under_root { ['Plant', plant_id] }
end
