# frozen_string_literal: true

module Types
  class SpecimenType
    # Adds a total_count field to the specimen connection
    class SpecimenConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(SpecimenEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
