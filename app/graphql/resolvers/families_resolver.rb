# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the families Query
  class FamiliesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::FamilyType::FamilyConnectionWithTotalCountType, null: false
    description 'Returns a list of Families'

    # Ordered by the untranslated scientific name, so unlike the other lookups
    # this does not need the .i18n scope for ordering. id breaks ties so the
    # offset-paginated connection cannot skip or repeat a row between pages.
    scope { Family.accepted.order(name: :asc).order(id: :asc) }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    option :name,
           type: String,
           with: :apply_name_filter,
           description: 'Performs a case-insensitive LIKE match on the scientific name'
    option :kingdom,
           type: String,
           with: :apply_kingdom_filter,
           description: 'Restrict to one of Plantae, Fungi or Chromista'
    option :plant_type,
           type: String,
           with: :apply_plant_type_filter,
           description: 'Restrict to a broad grouping such as Angiosperms or Fungi'
    option :has_pending_changes,
           type: Boolean,
           with: :apply_has_pending_changes_filter,
           description: 'Restrict to records with (true) or without (false) an open draft'

    # EXISTS (not a join, nil is "filter absent" not false) -- see the fuller
    # comment on the same method in varieties_resolver.rb.
    def apply_has_pending_changes_filter(scope, value)
      return scope if value.nil?

      scope.where("#{'NOT ' unless value}EXISTS (SELECT 1 FROM record_drafts WHERE draftable_type = 'Family' AND draftable_id = families.id)")
    end

    def apply_name_filter(scope, value)
      return scope if value.blank?

      scope.where('families.name ILIKE ?', "%#{value}%")
    end

    def apply_kingdom_filter(scope, value)
      return scope if value.blank?

      scope.where(kingdom: value)
    end

    def apply_plant_type_filter(scope, value)
      return scope if value.blank?

      scope.where(plant_type: value)
    end

    def apply_language_filter(scope, _value)
      # the language is actually applied in the fetch results method
      scope
    end

    def fetch_results
      Mobility.locale = language if language
      super
    end
  end
end
