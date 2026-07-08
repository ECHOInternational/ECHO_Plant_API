# frozen_string_literal: true

module Mutations
  module Concerns
    # Validates Postgres range literal strings supplied to range arguments.
    # Invalid literals become payload errors instead of raised cast errors.
    module RangeLiteralValidation
      RANGE_FIELDS = %i[
        n_accumulation_range biomass_production_range optimal_temperature_range
        optimal_rainfall_range seasonality_days_range optimal_altitude_range ph_range
      ].freeze

      RANGE_LITERAL = /\A[\[(]\s*-?\d*\.?\d*\s*,\s*-?\d*\.?\d*\s*[\])]\z/.freeze

      def validate_range_literals(attributes)
        RANGE_FIELDS.filter_map do |field|
          value = attributes[field]
          next if value.nil? || value.match?(RANGE_LITERAL)

          {
            field: field.to_s.camelize(:lower),
            message: "#{field} is not a valid range literal (expected e.g. \"[0,10]\")",
            code: 400
          }
        end
      end
    end
  end
end
