# frozen_string_literal: true

module Types
  # Defines fields for a Movement event
  class MovementEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Creates a Movement Life Cycle Event attached to the specified specimen'

    field :location, Types::LocationType,
          description: 'A location is an instance of a plant or a single group planting. See ID',
          null: false

    field :quantity, Float,
          description: '# of plants moved (transplanted)',
          null: true

    field :unit, Types::UnitEnum,
          description: 'Count or Weight(kg)',
          null: true

    field :between_row_spacing, Integer,
          description: 'cm between rows',
          null: true

    field :in_row_spacing, Integer,
          description: 'cm spacing between plants',
          null: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
