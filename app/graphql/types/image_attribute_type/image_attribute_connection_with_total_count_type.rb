# frozen_string_literal: true

module Types
  class ImageAttributeType
    # Adds a total_count field to the image attribute connection
    class ImageAttributeConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(ImageAttributeEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
