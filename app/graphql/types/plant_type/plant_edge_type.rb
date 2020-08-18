# frozen_string_literal: true

module Types
  class PlantType
    # The edge type for the plant type
    class PlantEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::PlantType)
    end
  end
end
