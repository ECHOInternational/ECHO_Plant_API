# frozen_string_literal: true

# Categories are groupings of plant objects
class Category < ApplicationRecord
  extend Mobility
  translates :name, :description
  validates :name, :owned_by, :created_by, :visibility, presence: true
  enum visibility: { private: 0, public: 1, draft: 2, deleted: 3 }, _prefix: :visibility
  has_many :images, as: :imageable, dependent: :destroy

  has_many :categories_plants, dependent: :destroy
  has_many :plants, through: :categories_plants

  def translations_array
    translations.map do |language, attributes|
      {
        locale: language,
        name: attributes['name'],
        description: attributes['description']
      }
    end
  end
end
