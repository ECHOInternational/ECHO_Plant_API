# frozen_string_literal: true

module Types
  # Defines fields for a Soil preparation event
  class SoilPreparationEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Describes actions taken to prepare for planting'

    field :soil_preparation, Types::SoilPreparationEnum,
          description: 'Indicates a type of soil preparation',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
