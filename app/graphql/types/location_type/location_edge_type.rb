# frozen_string_literal: true

module Types
  class LocationType
    # The edge type for the location type
    class LocationEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::LocationType)
    end
  end
end
