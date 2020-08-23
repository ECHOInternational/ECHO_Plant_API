# frozen_string_literal: true

module Types
  # Defines fields for a Harvest event
  class HarvestEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    field :quantity, Float,
          description: 'DESCRIPTION NEEDED',
          null: false

    field :unit, Types::UnitEnum,
          description: 'DESCRIPTION NEEDED',
          null: false

    field :quality, Integer,
          description: 'DESCRIPTION NEEDED',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
