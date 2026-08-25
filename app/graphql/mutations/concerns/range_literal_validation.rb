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

      # The opening bracket must always be "[" (never "("): Ruby's Range class
      # has no way to represent an open/exclusive lower bound at all -- when
      # the lower side carries a real value, assigning a literal like
      # "(5,10]" to a range attribute raises ActiveRecord::PostgreSQL's
      # underlying ArgumentError ("does not support excluding the beginning
      # of a Range") instead of failing validation. Excluding "(" here keeps
      # the promise in this module's file comment -- invalid literals become
      # payload errors, never raised cast errors -- and matches
      # RangeLiteral.serialize, which likewise never emits "(" as the lower
      # bracket (see app/services/range_literal.rb). The closing bracket
      # stays either "]" or ")": a finite exclusive upper bound (e.g.
      # "[1,2)") is a real, round-trippable literal the serializer can emit.
      RANGE_LITERAL = /\A\[\s*(-?(\d+\.?\d*|\.\d+))?\s*,\s*(-?(\d+\.?\d*|\.\d+))?\s*[\])]\z/.freeze

      def validate_range_literals(attributes)
        RANGE_FIELDS.filter_map do |field|
          value = attributes[field]
          next if value.nil? || value.match?(RANGE_LITERAL)

          camelized = field.to_s.camelize(:lower)
          {
            field: camelized,
            message: "#{camelized} is not a valid range literal (expected e.g. \"[0,10]\")",
            code: 400
          }
        end
      end
    end
  end
end
