# frozen_string_literal: true

module Types
  class VarietyType
    # Adds a total_count field to the variety connection
    class VarietyConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(VarietyEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
