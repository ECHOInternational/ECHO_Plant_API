# frozen_string_literal: true

# Relation table for Images and ImageAttributes
class ImageAttributesImage < ApplicationRecord
  belongs_to :image_attribute
  belongs_to :image
end
