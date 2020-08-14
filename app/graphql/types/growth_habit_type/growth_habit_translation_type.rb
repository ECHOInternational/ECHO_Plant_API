# frozen_string_literal: true

module Types
  class GrowthHabitType
    # Defines translated fields for an growth habit
    class GrowthHabitTranslationType < Types::BaseObject
      description 'Translated fields for an growth habit'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of an growth habit',
            null: false
    end
  end
end
