# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the plants Query
  class PlantsResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::PlantType::PlantConnectionWithTotalCountType, null: false
    description 'Returns a list of Plants'

    # Eager-load the two associations the list/detail responses read per plant
    # (primary_common_name resolves over common_names; the nested varieties
    # connection resolves through the varieties association). Without this the
    # mobile cache-priming query issues one common_names query per plant plus
    # one varieties query per plant (the classic N+1). Rails de-duplicates this
    # against the additional includes(:common_names) added by the name/any_name
    # filters, so those branches keep working.
    scope { Pundit.policy_scope(context[:current_user], Plant).i18n.includes(:common_names, :varieties) }

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
    option :owned_by_organization_id,
           type: GraphQL::Types::ID,
           with: :apply_owned_by_organization_id_filter,
           description: 'Returns only records owned by the specified organization (Relay global ID).'

    def apply_owned_by_filter(scope, value)
      return scope if value.blank?

      scope.where(owned_by: value)
    end

    def apply_owned_by_organization_id_filter(scope, value)
      return scope if value.blank?

      uuid = decode_organization_id(value)
      return scope.none if uuid.nil?

      scope.where(owner_organization_id: uuid)
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
      scope.order(scientific_name: :asc)
    end

    def apply_sort_direction_with_desc(scope)
      scope.order(scientific_name: :desc)
    end

    def apply_name_filter(scope, value)
      return scope if value.blank?

      # Filter via an EXISTS subquery instead of joining/referencing the
      # eager-loaded common_names association. A referenced where would turn the
      # includes into a filtered LEFT JOIN and truncate the loaded association
      # to only the matching rows, corrupting the loaded-aware
      # primary_common_name tier resolution. The subquery keeps the outer
      # includes(:common_names) loading the FULL association.
      scope.where(
        'EXISTS (SELECT 1 FROM common_names cn WHERE cn.plant_id = plants.id AND cn.name iLIKE :search)',
        search: "%#{value}%"
      )
    end

    def apply_scientific_name_filter(scope, value)
      return scope if value.blank?

      scope.where('scientific_name iLIKE ?', "%#{value}%")
    end

    def apply_any_name_filter(scope, value)
      return scope if value.blank?

      # Match on scientific_name OR any common name via an EXISTS subquery so the
      # eager-loaded common_names association is not truncated to matching rows
      # (see apply_name_filter). The outer includes(:common_names) still loads
      # the FULL association, keeping loaded-aware primary_common_name correct.
      scope.where(
        'plants.scientific_name iLIKE :search OR ' \
        'EXISTS (SELECT 1 FROM common_names cn WHERE cn.plant_id = plants.id AND cn.name iLIKE :search)',
        search: "%#{value}%"
      )
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
