# frozen_string_literal: true

module Types
  class ChangeEntryType
    # Adds a total_count field to the change entry connection
    class ChangeEntryConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(ChangeEntryEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
