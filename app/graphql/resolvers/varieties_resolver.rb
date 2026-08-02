# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the varieties query
  class VarietiesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::VarietyType::VarietyConnectionWithTotalCountType, null: false
    description 'Returns a list of Plant Varieties'

    scope { Pundit.policy_scope(context[:current_user], Variety).i18n }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
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
      # The id tiebreaker is not cosmetic. The Relay connection paginates by
      # OFFSET, so page 2 is a second query with OFFSET 25 rather than a
      # continuation of the first. Postgres gives no stable order for rows that
      # tie on the sort key, so without a deterministic final term two equal
      # rows can swap between those queries and a record is skipped or repeated
      # across a page boundary. Production has 13 duplicated scientific names.
      # Chained rather than order(name:, id:): on a Mobility .i18n scope the
      # translated key is rewritten into a jsonb expression and any other key
      # in the same hash is silently dropped, so the tiebreaker never reached
      # the SQL.
      scope.order(name: :asc).order(id: :asc)
    end

    def apply_sort_direction_with_desc(scope)
      # Chained rather than order(name:, id:): on a Mobility .i18n scope the
      # translated key is rewritten into a jsonb expression and any other key
      # in the same hash is silently dropped, so the tiebreaker never reached
      # the SQL.
      scope.order(name: :desc).order(id: :desc)
    end

    def apply_name_filter(scope, value)
      return scope if value.blank?

      scope.i18n do
        name.matches("%#{value}%")
      end
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
