# Relation table for Images and ImageAttributes
class AntinutrientsPlant < ApplicationRecord
  belongs_to :antinutrient
  belongs_to :plant
end
