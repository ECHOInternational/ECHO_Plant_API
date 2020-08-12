# frozen_string_literal: true

module Types
  # Defines fields for an ImageAttribute
  class ImageAttributeType < Types::BaseObject
    global_id_field :id

    description 'An attribute of an image.'

    field :uuid, ID, 'The internal database ID for an image attribute', null: false, method: :id
    field :name, String, 'The translated name of an image attribute', null: true
    field :translations, [Types::CategoryType::CategoryTranslationType], 'Translations of translatable category fields', null: false, method: :translations_array
  end
end
