# frozen_string_literal: true

module Types
  class KoppenZoneType
    # Adds a total_count field to the climate zone connection
    class KoppenZoneConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(KoppenZoneEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
