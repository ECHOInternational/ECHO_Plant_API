# frozen_string_literal: true

module Types
  module LifeCycleEventType
    # The edge type for the life cycle event type
    class LifeCycleEventEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::LifeCycleEventType)
    end
  end
end
