# frozen_string_literal: true

# Relation table for Categories and Plants
class CategoriesPlant < ApplicationRecord
  belongs_to :category
  belongs_to :plant
end
