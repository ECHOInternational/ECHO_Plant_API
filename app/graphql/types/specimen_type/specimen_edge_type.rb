# frozen_string_literal: true

module Types
  class SpecimenType
    # The edge type for the specimen type
    class SpecimenEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::SpecimenType)
    end
  end
end
