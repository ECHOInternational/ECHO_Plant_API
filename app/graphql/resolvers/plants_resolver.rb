# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the plants Query
  class PlantsResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::PlantType::PlantConnectionWithTotalCountType, null: false
    description 'Returns a list of Plants'

    scope { Pundit.policy_scope(context[:current_user], Plant).i18n }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    option :name,
           type: String,
           with: :apply_name_filter,
           description: 'Performs a case-insensitive LIKE match on common names'
    option :scientific_name,
           type: String,
           with: :apply_scientific_name_filter,
           description: 'Performs a case-insensitive LIKE match on scientific names'
    option :any_name,
           type: String,
           with: :apply_any_name_filter,
           description: 'Performs a case-insensitive LIKE match on all name fields'
    option :visibility,
           type: Types::VisibilityEnum,
           default: :visible
    option :sort_direction,
           type: Types::SortDirectionEnum,
           default: :asc,
           description: 'Sorts by scientific name either ascending or descending'
    option :owned_by,
           type: String,
           with: :apply_owned_by_filter,
           description: 'Returns only records owned by the specified user'

    def apply_owned_by_filter(scope, value)
      return scope if value.blank?

      scope.where(owned_by: value)
    end

    def apply_visibility_with_private(scope)
      scope.visibility_private
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
      scope.order(scientific_name: :asc)
    end

    def apply_sort_direction_with_desc(scope)
      scope.order(scientific_name: :desc)
    end

    def apply_name_filter(scope, value)
      return scope if value.blank?

      scope
        .includes(:common_names)
        .where('common_names.name iLIKE ?', "%#{value}%")
        .references(:common_names)
    end

    def apply_scientific_name_filter(scope, value)
      return scope if value.blank?

      scope.where('scientific_name iLIKE ?', "%#{value}%")
    end

    def apply_any_name_filter(scope, value)
      return scope if value.blank?

      scope
        .includes(:common_names)
        .where('common_names.name iLIKE :search OR scientific_name iLIKE :search', { search: "%#{value}%" })
        .references(:common_names)
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
