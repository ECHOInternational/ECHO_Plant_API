# frozen_string_literal: true

# Relation table for Antinutrients and Plants
class AntinutrientsPlant < ApplicationRecord
  belongs_to :antinutrient
  belongs_to :plant
end
