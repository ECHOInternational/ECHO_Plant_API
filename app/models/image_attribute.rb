# frozen_string_literal: true

# ImageAttributes provide metadata for image objects
class ImageAttribute < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true
  # Locales without a name are skipped: the GraphQL translation type declares
  # name non-null, so one nameless entry would fail the whole field.
  def translations_array
    translations.filter_map do |language, attributes|
      { locale: language, name: attributes['name'] } if attributes['name'].present?
    end
  end
  has_many :image_attributes_image, dependent: :destroy
  has_many :images, through: :image_attributes_image
end
