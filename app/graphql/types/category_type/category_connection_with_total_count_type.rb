# frozen_string_literal: true

module Types
  class CategoryType
    # Adds a total_count field to the category connection
    class CategoryConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(CategoryEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
