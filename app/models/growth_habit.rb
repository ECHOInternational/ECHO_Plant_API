# frozen_string_literal: true

# Plants and varieties can have associated growth habits
class GrowthHabit < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true

  has_many :growth_habits_plants, dependent: :destroy
  has_many :plants, through: :growth_habits_plants

  has_many :growth_habits_varieties, dependent: :destroy
  has_many :varieties, through: :growth_habits_varieties

  # Locales without a name are skipped: the GraphQL translation type declares
  # name non-null, so one nameless entry would fail the whole field.
  def translations_array
    translations.filter_map do |language, attributes|
      next if attributes['name'].blank?

      {
        locale: language,
        name: attributes['name']
      }
    end
  end
end
