# frozen_string_literal: true

# Relation table for Köppen climate zones and Plants
class KoppenZonesPlant < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :koppen_zone
  belongs_to :plant

  versioned_under_root { ['Plant', plant_id] }
end
