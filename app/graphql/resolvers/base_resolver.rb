# frozen_string_literal: true

# app/graphql/resolvers/base.rb
module Resolvers
  # All resolvers inherit from this set of defaults
  class BaseResolver < GraphQL::Schema::Resolver
    private

    # Decodes an Organization Relay global ID to its underlying UUID, returning
    # nil for a blank or malformed id. Filters treat a nil result as "match
    # nothing" (scope.none) rather than raising, so a garbage id yields an empty
    # collection instead of a 500 -- mirroring the single-object queries which
    # return a coded 404 for malformed ids (a filter has no single record to
    # 404 on, so an empty result is the closest equivalent).
    def decode_organization_id(value)
      return nil if value.blank?

      _type, uuid = GraphQL::Schema::UniqueWithinType.decode(value)
      uuid
    rescue ArgumentError, GraphQL::ExecutionError
      nil
    end
  end
end
