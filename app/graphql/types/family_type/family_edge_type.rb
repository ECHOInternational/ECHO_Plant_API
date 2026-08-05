# frozen_string_literal: true

module Types
  class FamilyType
    # The edge type for the family type
    class FamilyEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::FamilyType)
    end
  end
end
