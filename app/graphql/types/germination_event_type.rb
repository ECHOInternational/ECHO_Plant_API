# frozen_string_literal: true

module Types
  # Defines fields for a Germination event
  class GerminationEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    field :percent, Integer,
          description: 'DESCRIPTION NEEDED',
          null: true

    field :quality, Integer,
          description: 'DESCRIPTION NEEDED',
          null: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
