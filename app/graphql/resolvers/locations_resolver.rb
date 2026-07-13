# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the locations Query
  class LocationsResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::LocationType::LocationConnectionWithTotalCountType, null: false
    description 'Returns a list of locations'

    scope { Pundit.policy_scope(context[:current_user], Location) }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    option :name,
           type: String,
           with: :apply_name_filter,
           description: 'Performs a case-insensitive LIKE match on the name field'
    option :visibility,
           type: Types::VisibilityEnum,
           default: :visible
    option :sort_direction,
           type: Types::SortDirectionEnum,
           default: :asc,
           description: 'Sorts by name either ascending or descending'
    option :owned_by,
           type: String,
           with: :apply_owned_by_filter,
           description: 'Returns only records owned by the specified user'

    def apply_owned_by_filter(scope, value)
      return scope if value.blank?

      scope.where(owned_by: value)
    end

    def apply_visibility_with_private(scope)
      # The legacy PRIVATE filter historically meant "my own private records"
      # (pre-redesign the policy scope was public-or-owned, so private records a
      # user could see were only their own). The organization scope union would
      # otherwise inject org-owned private records here, which the frozen mobile
      # client treats as personal and would sync/edit. Preserve the historical
      # contract: own-only for non-admins; admins keep the all-private view.
      user = context[:current_user]
      scoped = scope.visibility_private
      return scoped if user.nil? || user.admin?

      scoped.where(owned_by: user.email)
    end

    def apply_visibility_with_public(scope)
      scope.visibility_public
    end

    def apply_visibility_with_draft(scope)
      scope.visibility_draft
    end

    def apply_visibility_with_deleted(scope)
      scope.visibility_deleted
    end

    def apply_visibility_with_visible(scope)
      scope.where(visibility: %i[public private])
    end

    def apply_sort_direction_with_asc(scope)
      scope.order(name: :asc)
    end

    def apply_sort_direction_with_desc(scope)
      scope.order(name: :desc)
    end

    def apply_name_filter(scope, value)
      return scope if value.blank?

      scope.where('name iLIKE ?', "%#{value}%")
    end

    def apply_language_filter(scope, _value)
      # the language is actually applied in the fetch results method
      scope
    end

    def fetch_results
      # Set the requested language
      Mobility.locale = language if language
      # Because we're "including"  the translations we can get duplicates, eliminate them before returning.
      # super.uniq
      super
    end
  end
end
