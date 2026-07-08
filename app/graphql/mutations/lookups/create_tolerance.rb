# frozen_string_literal: true

module Mutations
  module Lookups
    # Creates a Tolerance
    class CreateTolerance < CreateLookupBaseMutation
      lookup_model Tolerance, type: Types::ToleranceType
    end
  end
end
