# frozen_string_literal: true

# Plants and varieties can have associated antinutrients
class Antinutrient < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true
  def translations_array
    translations.map do |language, attributes|
      {
        locale: language,
        name: attributes['name']
      }
    end
  end
end
