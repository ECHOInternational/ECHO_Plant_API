# frozen_string_literal: true

module Types
  # Defines fields for a Pruning event
  class PruningEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Actions taken to prune plants for better production'

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
