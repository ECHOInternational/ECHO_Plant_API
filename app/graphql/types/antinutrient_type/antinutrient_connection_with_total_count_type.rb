# frozen_string_literal: true

module Types
  class AntinutrientType
    # Adds a total_count field to the image attribute connection
    class AntinutrientConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(AntinutrientEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
