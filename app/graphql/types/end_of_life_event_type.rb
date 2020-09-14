# frozen_string_literal: true

module Types
  # Defines fields for a End of life event
  class EndOfLifeEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Actions taken when plant(s) stop producing - at least notation of such'

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
