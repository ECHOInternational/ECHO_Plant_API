# frozen_string_literal: true

module Types
  # Defines fields for a Acquire event
  class AcquireEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'DESCRIPTION NEEDED'

    field :condition, Types::ConditionEnum,
          description: 'DESCRIPTION NEEDED',
          null: false

    field :accession, String,
          description: 'DESCRIPTION NEEDED',
          null: true

    field :source, String,
          description: 'DESCRIPTION NEEDED',
          null: false

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
