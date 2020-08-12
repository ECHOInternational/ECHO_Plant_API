# frozen_string_literal: true

module Types
  # Defines fields for an Image
  class ImageType < Types::BaseObject
    global_id_field :id

    description 'Images can be associated with most data types in the Plant API'

    field :uuid, ID,
          description: 'The internal database ID for an image',
          null: false,
          method: :id
    field :name, String,
          description: 'The translated name of an image',
          null: true
    field :description, String,
          description: 'A translated description of an image',
          null: true
    field :attribution, String,
          description: 'Copyright and attribution data',
          null: true
    field :base_url, String,
          description: 'The URL for the image',
          null: false
    field :image_attributes, [Types::ImageAttributeType],
          description: 'A list of attributes for this image',
          null: false
    field :created_by, String,
          description: "The user ID of an image's creator",
          null: true
    field :owned_by, String,
          description: "The user ID of an image's owner",
          null: true
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable category fields',
          null: false,
          method: :translations_array
  end
end
