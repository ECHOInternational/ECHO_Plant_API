# frozen_string_literal: true

module Types
  class AntinutrientType
    # The edge type for the image attribute type
    class AntinutrientEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::AntinutrientType)
    end
  end
end
