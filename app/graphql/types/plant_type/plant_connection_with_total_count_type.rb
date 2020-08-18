# frozen_string_literal: true

module Types
  class PlantType
    # Adds a total_count field to the plant connection
    class PlantConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(PlantEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
