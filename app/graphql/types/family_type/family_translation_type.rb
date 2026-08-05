# frozen_string_literal: true

module Types
  class FamilyType
    # Translated fields for a family
    class FamilyTranslationType < Types::BaseObject
      description 'Translated fields for a family'

      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :description, String,
            description: 'The translated description of a family',
            null: true
      field :seed_banking_notes, String,
            description: 'The translated seed banking notes for a family',
            null: true
    end
  end
end
