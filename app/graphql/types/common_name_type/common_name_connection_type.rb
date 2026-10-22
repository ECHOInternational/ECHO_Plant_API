# frozen_string_literal: true

module Types
  class CommonNameType
    # The CommonName connection with a totalCount (FPI plan API-8). Installed
    # as CommonNameType's connection_type_class, so the GraphQL type keeps its
    # name, CommonNameConnection, and existing documents are unaffected.
    class CommonNameConnectionType < GraphQL::Types::Relay::BaseConnection
      field :total_count, Integer, null: false,
                                   description: 'The number of names matching the arguments, across all pages.'

      def total_count
        object.items.size
      end
    end
  end
end
