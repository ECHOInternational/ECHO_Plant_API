# frozen_string_literal: true

module Types
  # Defines fields for a Soil preparation event
  class SoilPreparationEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    field :soil_preparation, Types::SoilPreparationEnum,
          description: 'DESCRIPTION NEEDED',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
