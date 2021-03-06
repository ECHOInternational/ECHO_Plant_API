# frozen_string_literal: true

module Types
  class CategoryType
    # Defines translated fields for a category
    class CategoryTranslationType < Types::BaseObject
      description 'Translated fields for a Category'
      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :name, String,
            description: 'The translated name of a category',
            null: false
      field :description, String,
            description: 'A translated description of a category',
            null: true
    end
  end
end
