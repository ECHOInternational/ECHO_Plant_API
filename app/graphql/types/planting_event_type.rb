# frozen_string_literal: true

module Types
  # Defines fields for a Planting event
  class PlantingEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    field :location, Types::LocationType,
          description: 'DESCRIPTION NEEDED',
          null: false

    field :quantity, Float,
          description: 'DESCRIPTION NEEDED',
          null: true

    field :unit, Types::UnitEnum,
          description: 'DESCRIPTION NEEDED',
          null: true

    field :between_row_spacing, Integer,
          description: 'DESCRIPTION NEEDED',
          null: true

    field :in_row_spacing, Integer,
          description: 'DESCRIPTION NEEDED',
          null: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
