# frozen_string_literal: true

module Types
  # Defines fields for a Thinning event
  class ThinningEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end