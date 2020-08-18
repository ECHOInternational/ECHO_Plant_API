# frozen_string_literal: true

module Types
  class GrowthHabitType
    # Adds a total_count field to the growth habit connection
    class GrowthHabitConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(GrowthHabitEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
