# frozen_string_literal: true

module Types
  class GrowthHabitType
    # The edge type for the growth habit type
    class GrowthHabitEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::GrowthHabitType)
    end
  end
end
