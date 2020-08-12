# frozen_string_literal: true

module Types
  # Defines fields for an ImageAttribute - categories contains a group of plant objects
  class ImageAttributeType < Types::BaseObject
    global_id_field :id

    description 'An attribute of an image.'

    field :uuid, ID,
          description: 'The internal database ID for an image attribute',
          null: false,
          method: :id
    field :name, String,
          description: 'The translated name of an image attribute',
          null: true
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable category fields',
          null: false,
          method: :translations_array
  end
end
