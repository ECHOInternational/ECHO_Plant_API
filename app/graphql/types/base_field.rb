# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field # :nodoc:
    argument_class Types::BaseArgument

    # The page size query-complexity analysis assumes for a connection that
    # was given neither first: nor last: and has no configured page size.
    #
    # graphql-ruby multiplies a connection's child complexity by its page
    # size, and RAISES ("Can't calculate complexity") when it cannot find
    # one. Most connections here are deliberately uncapped -- a schema-wide
    # default_max_page_size would truncate the frozen mobile app's
    # unpaginated plants() full sync and its nested varieties/images lists
    # -- so without this every such query would fail outright once
    # PlantApiSchema sets max_complexity.
    #
    # What an unbounded connection can actually return is bounded elsewhere:
    # the root plants() full sync by MobileFullSyncGuard, nested lists
    # (varieties, images, common names of one plant) by the data. 25 is the
    # page size the API's own clients use for a list (ECHOcommunity's
    # PlantApi::Client::PAGE_SIZE, the admin SPA's DEFAULT_PAGE_SIZE).
    UNBOUNDED_CONNECTION_PAGE_SIZE = 25

    def calculate_complexity(query:, nodes:, child_complexity:)
      return super unless unbounded_connection?(query, nodes)

      # The same shape as graphql-ruby's connection formula, but with the
      # page multiplier applied to the whole child complexity (pageInfo and
      # totalCount included): a slight over-count, never an under-count.
      own = complexity.is_a?(Numeric) ? complexity : 1
      own + (UNBOUNDED_CONNECTION_PAGE_SIZE * child_complexity)
    end

    private

    def unbounded_connection?(query, nodes)
      return false unless connection? && !respond_to?(:complexity_for)
      return false if configured_page_size?(query)

      arguments = query.arguments_for(nodes.first, self)
      # Argument errors are raised by super, as graphql-ruby does.
      arguments.respond_to?(:[]) && arguments[:first].nil? && arguments[:last].nil?
    end

    def configured_page_size?(query)
      schema = query.schema
      !(default_page_size || schema.default_page_size || max_page_size || schema.default_max_page_size).nil?
    end
  end
end
