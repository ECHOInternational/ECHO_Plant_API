# frozen_string_literal: true

# Relation table for Tolerances and Plants
class TolerancesPlant < ApplicationRecord
  belongs_to :tolerance
  belongs_to :plant
end
