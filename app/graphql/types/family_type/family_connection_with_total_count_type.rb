# frozen_string_literal: true

module Types
  class FamilyType
    # Adds a total_count field to the family connection
    class FamilyConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(FamilyEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
