# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the categories Query
  class CategoriesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::CategoryType::CategoryConnectionWithTotalCountType, null: false
    description 'Returns a list of Plant Categories'

    # record_draft is eager-loaded because it backs the draft field added by
    # Types::Concerns::DraftFields; without it a list request for that field
    # issues one record_drafts query per row.
    scope { Pundit.policy_scope(context[:current_user], Category).i18n.includes(:record_draft) }

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
    option :has_pending_changes,
           type: Boolean,
           with: :apply_has_pending_changes_filter,
           description: 'Restrict to records with (true) or without (false) an open draft'

    # EXISTS (not a join, nil is "filter absent" not false) -- see the fuller
    # comment on the same method in varieties_resolver.rb.
    def apply_has_pending_changes_filter(scope, value)
      return scope if value.nil?

      scope.where("#{'NOT ' unless value}EXISTS (SELECT 1 FROM record_drafts WHERE draftable_type = 'Category' AND draftable_id = categories.id)")
    end

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
