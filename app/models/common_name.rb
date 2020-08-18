# frozen_string_literal: true

# Defines the Common Name type as a related attribute of plants
class CommonName < ApplicationRecord
  belongs_to :plant
  validates :name, :language, :plant, presence: true
end
