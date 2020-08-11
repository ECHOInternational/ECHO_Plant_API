# frozen_string_literal: true

module Types
  class ImageAttributeType
    class ImageAttributeEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::ImageAttributeType)
    end
  end
end
