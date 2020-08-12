# frozen_string_literal: true

# ImageAttributes provide metadata for image objects
class ImageAttribute < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true
  def translations_array
    translations.map { |language, attributes| { locale: language, name: attributes['name'] } }
  end
  has_many :image_attributes_image, dependent: :destroy
  has_many :images, through: :image_attributes_image
end
