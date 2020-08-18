# frozen_string_literal: true

module Types
  class ToleranceType
    # Defines translated fields for a tolerance
    class ToleranceTranslationType < Types::BaseObject
      description 'Translated fields for a tolerance'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of an tolerance',
            null: false
    end
  end
end
