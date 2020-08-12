# frozen_string_literal: true

module Types
  class ImageAttributeType
    # The edge type for the image attribute type
    class ImageAttributeEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::ImageAttributeType)
    end
  end
end
