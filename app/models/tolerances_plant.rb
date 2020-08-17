class TolerancesPlant < ApplicationRecord
  belongs_to :tolerance
  belongs_to :plant
end
