# frozen_string_literal: true

# Relation table for Antinutrients and Varieties
class AntinutrientsVariety < ApplicationRecord
  belongs_to :antinutrient
  belongs_to :variety
end
