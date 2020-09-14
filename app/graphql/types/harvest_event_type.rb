# frozen_string_literal: true

module Types
  # Defines fields for a Harvest event
  class HarvestEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Creates a Harvest Life Cycle Event attached to the specified specimen'

    field :quantity, Float,
          description: 'Total harvest units for a single harvest event - may be multiple harvest events',
          null: false

    field :unit, Types::UnitEnum,
          description: 'Indicates the unit of associated value (Weight in kg,Count)',
          null: false

    field :quality, Integer,
          description: 'Rate 1-10, 10 best',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
