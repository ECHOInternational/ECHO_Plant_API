# frozen_string_literal: true

# app/graphql/resolvers/base.rb
module Resolvers
  # All resolvers inherit from this set of defaults
  class BaseResolver < GraphQL::Schema::Resolver
  end
end
