# frozen_string_literal: true

module Types
  class KoppenZoneType
    # Defines translated fields for a climate zone
    class KoppenZoneTranslationType < Types::BaseObject
      description 'Translated fields for a climate zone'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of a climate zone',
            null: true
      field :description, String,
            description: 'The translated description of a climate zone',
            null: true
    end
  end
end
