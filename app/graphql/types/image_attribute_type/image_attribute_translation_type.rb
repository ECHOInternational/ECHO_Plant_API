# frozen_string_literal: true

module Types
  class ImageAttributeType
    class ImageAttributeTranslationType < Types::BaseObject
      description 'Translated fields for an image attribute'
      field :locale, String, 'The locale for this translation', null: false
      field :name, String, 'The translated name of an image attribute', null: false
    end
  end
end
