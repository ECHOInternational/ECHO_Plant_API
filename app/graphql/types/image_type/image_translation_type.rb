# frozen_string_literal: true

module Types
  class ImageType
    # Defines translated fields for an image. Unlike lookup records, an image
    # can legitimately hold a locale that has only one of the two fields, so
    # both are nullable.
    class ImageTranslationType < Types::BaseObject
      description 'Translated fields for an Image'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of an image',
            null: true
      field :description, String,
            description: 'A translated description of an image',
            null: true
    end
  end
end
