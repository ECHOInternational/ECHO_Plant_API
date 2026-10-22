# frozen_string_literal: true

module Extensions
  # A connection extension that rejects an explicit first:/last: above
  # MAX_PAGE_SIZE with a coded GraphQL error, instead of silently clamping.
  #
  # Used on every plants connection (root, Category.plants, Family.plants).
  # A clamp (max_page_size) would hand a client that asked for 1,000 rows a
  # short page that looks complete; the error says what happened. Omitting
  # both arguments is not affected here: the root field's unpaginated call
  # belongs to the frozen mobile app and is governed by
  # GuardedConnectionExtension, and the nested fields keep their own
  # max_page_size or are bounded by their parent.
  class PageSizeLimitedConnectionExtension < GraphQL::Schema::Field::ConnectionExtension
    MAX_PAGE_SIZE = 500

    def resolve(object:, arguments:, context:, &block)
      %i[first last].each do |name|
        value = arguments[name]
        next if value.nil? || value <= MAX_PAGE_SIZE

        raise GraphQL::ExecutionError.new(
          "#{name}: #{value} exceeds the maximum page size of #{MAX_PAGE_SIZE} on " \
          "#{field.graphql_name}. Page through the connection with after:/before: instead.",
          extensions: { 'code' => 400 }
        )
      end

      super
    end
  end
end
