# frozen_string_literal: true

module Types
  # Defines fields for a Other event
  class OtherEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Actions taken concerning Lifecycle Events not in the list'

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
