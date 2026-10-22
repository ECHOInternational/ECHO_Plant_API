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

  # The attribute that marks an image as a drawing (FPI plan API-5). Matched by
  # its English name in raw SQL, never through the caller's Mobility locale, so
  # a request in fr or es still recognises it. Not keyed by id: the row is
  # created per environment (FpiImageImporter) and ids differ.
  DRAWING_NAME = 'Drawing'

  def self.drawing
    where("image_attributes.translations->'en'->>'name' = ?", DRAWING_NAME)
  end

  # Ids of every image tagged as a drawing, as a Set.
  def self.drawing_image_ids
    ImageAttributesImage.where(image_attribute_id: drawing.select(:id)).pluck(:image_id).to_set
  end
end
