# frozen_string_literal: true

module Types
  # Defines fields for an ImageAttribute - categories contains a group of plant objects
  class AntinutrientType < Types::BaseObject
    global_id_field :id

    description 'Antinutrients are natural or synthetic compounds that interfere with the absorption of nutrients.'

    field :uuid, ID,
          description: 'The internal database ID for an antinutrient',
          null: false,
          method: :id
    field :name, String,
          description: 'The translated name of an antinutrient',
          null: true
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable antinutrient fields',
          null: false,
          method: :translations_array
  end
end
