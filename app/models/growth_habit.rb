# frozen_string_literal: true

# Plants and varieties can have associated growth habits
class GrowthHabit < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true

  has_many :growth_habits_plants, dependent: :destroy
  has_many :plants, through: :growth_habits_plants

  def translations_array
    translations.map do |language, attributes|
      {
        locale: language,
        name: attributes['name']
      }
    end
  end
end
