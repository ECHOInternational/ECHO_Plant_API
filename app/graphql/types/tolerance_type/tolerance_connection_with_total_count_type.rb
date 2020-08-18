# frozen_string_literal: true

module Types
  class ToleranceType
    # Adds a total_count field to the image attribute connection
    class ToleranceConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(ToleranceEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
