# frozen_string_literal: true

class ImageAttributesImage < ApplicationRecord
  belongs_to :image_attribute
  belongs_to :image
end
