# frozen_string_literal: true

module Types
  class ToleranceType
    # The edge type for the image attribute type
    class ToleranceEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::ToleranceType)
    end
  end
end
