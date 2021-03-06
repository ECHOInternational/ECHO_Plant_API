# frozen_string_literal: true

module Types
  class ImageAttributeType
    # Defines translated fields for an image attribute
    class ImageAttributeTranslationType < Types::BaseObject
      description 'Translated fields for an image attribute'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of an image attribute',
            null: false
    end
  end
end
