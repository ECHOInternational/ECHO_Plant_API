# frozen_string_literal: true

module Types
  # Defines fields for an GrowthHabit - categories contains a group of plant objects
  class GrowthHabitType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'The shape, height, appearance, and form of growth of a plant'

    field :uuid, ID,
          description: 'The internal database ID for an growth habit',
          null: false,
          method: :id
    field :name, String,
          description: 'The translated name of an growth habit',
          null: true
    field :translations, [Types::CategoryType::CategoryTranslationType],
          description: 'Translations of translatable growth habit fields',
          null: false,
          method: :translations_array
  end
end
