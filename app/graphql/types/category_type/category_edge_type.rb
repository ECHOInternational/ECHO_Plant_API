# frozen_string_literal: true

module Types
  class CategoryType
    # The edge type for the category type
    class CategoryEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::CategoryType)
    end
  end
end
