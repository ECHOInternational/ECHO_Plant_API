# frozen_string_literal: true

FactoryBot.define do
  factory :image_attributes_image do
    image_attribute { build(:image_attribute) }
    image { build(:image) }
  end
end
