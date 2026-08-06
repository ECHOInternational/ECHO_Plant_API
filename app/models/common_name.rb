# frozen_string_literal: true

# Defines the Common Name type as a related attribute of plants
class CommonName < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :plant
  validates :name, :language, :plant, presence: true

  versioned_under_root { ['Plant', plant_id] }
end
