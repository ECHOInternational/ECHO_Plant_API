# frozen_string_literal: true

module Types
  class VarietyType
    # The edge type for the variety type
    class VarietyEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::VarietyType)
    end
  end
end
