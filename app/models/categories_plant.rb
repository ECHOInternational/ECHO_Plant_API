class CategoriesPlant < ApplicationRecord
  belongs_to :category
  belongs_to :plant
end
