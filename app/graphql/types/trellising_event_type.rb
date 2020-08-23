# frozen_string_literal: true

module Types
  # Defines fields for a Trellising event
  class TrellisingEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
