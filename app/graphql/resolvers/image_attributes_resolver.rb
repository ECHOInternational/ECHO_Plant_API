# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the imageAttributes Query
  class ImageAttributesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::ImageAttributeType::ImageAttributeConnectionWithTotalCountType, null: false
    description 'Returns a list of Image Attributes'

    # id breaks ties so the offset-paginated connection cannot skip or repeat a
    # row between pages (see PlantsResolver). Chained, not a second key in the
    # same hash: .i18n rewrites the translated key and drops the rest.
    scope { ImageAttribute.all.i18n.order(name: :asc).order(id: :asc) }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific languge. Overrides ACCEPT-LANGUAGE header.'
    option :name,
           type: String,
           with: :apply_name_filter,
           description: 'Performs a case-insensitive LIKE match on the name field'

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
      Mobility.locale = language if language
      super
    end
  end
end
