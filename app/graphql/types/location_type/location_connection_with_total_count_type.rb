# frozen_string_literal: true

module Types
  class LocationType
    # Adds a total_count field to the location connection
    class LocationConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(LocationEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
