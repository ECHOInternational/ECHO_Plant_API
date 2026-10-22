# frozen_string_literal: true

# Categories are groupings of plant objects
class Category < ApplicationRecord
  include OrganizedResource
  include Draftable

  extend Mobility
  translates :name, :description
  validates :name, :owned_by, :created_by, :visibility, presence: true
  enum :visibility, { private: 0, public: 1, draft: 2, deleted: 3 }, prefix: :visibility
  has_many :images, as: :imageable, dependent: :destroy

  has_many :categories_plants, dependent: :destroy
  has_many :plants, through: :categories_plants

  # Locales without a name are skipped: CategoryTranslationType declares name
  # non-null, and writing only `description` in a new locale creates a
  # nameless entry (the field-order trap).
  def translations_array
    translations.filter_map do |language, attributes|
      next if attributes['name'].blank?

      {
        locale: language,
        name: attributes['name'],
        description: attributes['description']
      }
    end
  end
end
