# frozen_string_literal: true

# Plants and varieties can have associated antinutrients
class Tolerance < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true

  has_many :tolerances_plants, dependent: :destroy
  has_many :plants, through: :tolerances_plants

  has_many :tolerances_varieties, dependent: :destroy
  has_many :varieties, through: :tolerances_varieties

  def translations_array
    translations.map do |language, attributes|
      {
        locale: language,
        name: attributes['name']
      }
    end
  end
end
