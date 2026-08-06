# frozen_string_literal: true

module Types
  class ChangeEntryType
    # The edge type for the change entry type
    class ChangeEntryEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::ChangeEntryType)
    end
  end
end
