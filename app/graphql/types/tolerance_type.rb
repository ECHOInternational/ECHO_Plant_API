# frozen_string_literal: true

module Types
  # Defines fields for a tolerance - attribute of a plant or variety
  class ToleranceType < Types::BaseObject
    global_id_field :id

    description 'Tolerances indicate that a plant or variety is uniquely suited to deal with an adverse condition.'

    field :uuid, ID,
          description: 'The internal database ID for a tolerance',
          null: false,
          method: :id
    field :name, String,
          description: 'The translated name of a tolerance',
          null: true
    field :translations, [Types::ToleranceType::ToleranceTranslationType],
          description: 'Translations of translatable tolerance fields',
          null: false,
          method: :translations_array
  end
end
