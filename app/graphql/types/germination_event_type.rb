# frozen_string_literal: true

module Types
  # Defines fields for a Germination event
  class GerminationEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Creates a Germination Life Cycle Event attached to the specified specimen'

    field :percent, Integer,
          description: 'Germination percentage is an estimate of the viability of a population of seeds',
          null: true

    field :quality, Integer,
          description: 'Rate 1-10, 10 best',
          null: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
