# frozen_string_literal: true

module Types
  module LifeCycleEventType
    # Adds a total_count field to the life cycle event connection
    class LifeCycleEventConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(LifeCycleEventEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
