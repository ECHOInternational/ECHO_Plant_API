# frozen_string_literal: true

module Types
  # Defines fields for an Antinutrient - attribute of a plant or variety
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
    field :translations, [Types::AntinutrientType::AntinutrientTranslationType],
          description: 'Translations of translatable antinutrient fields',
          null: false,
          method: :translations_array
  end
end
