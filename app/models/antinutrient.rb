# frozen_string_literal: true

# Plants and varieties can have associated antinutrients
class Antinutrient < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true

  has_many :antinutrients_plants, dependent: :destroy
  has_many :plants, through: :antinutrients_plants

  has_many :antinutrients_varieties, dependent: :destroy
  has_many :varieties, through: :antinutrients_varieties

  def translations_array
    translations.map do |language, attributes|
      {
        locale: language,
        name: attributes['name']
      }
    end
  end
end
