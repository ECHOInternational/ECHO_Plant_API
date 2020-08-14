# frozen_string_literal: true

module Types
  class AntinutrientType
    # Defines translated fields for an antinutrient
    class AntinutrientTranslationType < Types::BaseObject
      description 'Translated fields for an antinutrient'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of an antinutrient',
            null: false
    end
  end
end
