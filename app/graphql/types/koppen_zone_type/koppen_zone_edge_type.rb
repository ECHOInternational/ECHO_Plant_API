# frozen_string_literal: true

module Types
  class KoppenZoneType
    # The edge type for the climate zone type
    class KoppenZoneEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::KoppenZoneType)
    end
  end
end
