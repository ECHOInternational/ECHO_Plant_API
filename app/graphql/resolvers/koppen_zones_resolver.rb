# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the koppenZones Query
  class KoppenZonesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::KoppenZoneType::KoppenZoneConnectionWithTotalCountType, null: false
    description 'Returns a list of Köppen-Geiger climate zones'

    # Ordered by `position`, which encodes the classification's own sequence
    # (groups, then subgroups, then classes) rather than alphabetical order, so
    # a client rendering the tree does not have to re-sort. id breaks ties so
    # the offset-paginated connection cannot skip or repeat a row between
    # pages, matching the other lookup resolvers.
    scope { KoppenZone.all.order(:position).order(:id) }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    option :code,
           type: String,
           with: :apply_code_filter,
           description: 'Exact, case-insensitive match on the Köppen code'
    option :level,
           type: String,
           with: :apply_level_filter,
           description: 'Restrict to group, subgroup or class'
    option :authoritative,
           type: Boolean,
           with: :apply_authoritative_filter,
           description: 'Restrict to zones that do (true) or do not (false) appear in ' \
                        'Beck et al. 2018'

    def apply_code_filter(scope, value)
      return scope if value.blank?

      scope.where('lower(code) = ?', value.downcase)
    end

    def apply_level_filter(scope, value)
      return scope if value.blank?

      scope.where(level: value)
    end

    def apply_authoritative_filter(scope, value)
      return scope if value.nil?

      scope.where(authoritative: value)
    end
  end
end
