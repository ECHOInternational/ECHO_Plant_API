# frozen_string_literal: true

module Types
  # Defines fields for a Mulching event
  class MulchingEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Actions taken to apply a protective covering on the soil to preserve moisture/fertility '

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
