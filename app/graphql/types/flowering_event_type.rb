# frozen_string_literal: true

module Types
  # Defines fields for a Flowering event
  class FloweringEventType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node
    implements Types::LifeCycleEventType

    description 'Days to 50% Flowering'

    field :percent, Integer,
          description: 'Days to 50% flowering is determined by recording the number of days until 50% of plants in a plot had at least one open flower',
          null: true

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end
  end
end
