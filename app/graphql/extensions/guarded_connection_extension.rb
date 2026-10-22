# frozen_string_literal: true

module Extensions
  # The root plants() connection: the page-size limit, plus the mobile
  # full-sync guard (MobileFullSyncGuard.restrict_full_sync) on a call that
  # gives neither first: nor last:.
  #
  # This has to live in the connection extension. graphql-ruby strips the
  # pagination arguments before the resolver runs
  # (GraphQL::Schema::Field::ConnectionExtension#resolve), so
  # PlantsResolver cannot tell "no first:" from "first: 25". The extension
  # receives the original arguments back as `memo` in after_resolve, before
  # the relation is wrapped in a connection, which is also before totalCount
  # and the page slice are computed from it.
  class GuardedConnectionExtension < PageSizeLimitedConnectionExtension
    def after_resolve(value:, object:, arguments:, context:, memo:)
      value = MobileFullSyncGuard.restrict_full_sync(value, context[:current_user]) if guard?(value, memo)

      super
    end

    private

    # memo is nil only if resolve never yielded; that counts as unpaginated,
    # so the guard fails closed. Anything other than a relation raises in
    # restrict_full_sync rather than passing through unguarded.
    def guard?(value, memo)
      return false if value.nil? || value.is_a?(GraphQL::ExecutionError)

      original = memo || {}
      original[:first].nil? && original[:last].nil?
    end
  end
end
