# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the tolerances Query
  class TolerancesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::ToleranceType::ToleranceConnectionWithTotalCountType, null: false
    description 'Returns a list of Tolerances'

    scope { Tolerance.all.i18n.order(name: :asc) }

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
