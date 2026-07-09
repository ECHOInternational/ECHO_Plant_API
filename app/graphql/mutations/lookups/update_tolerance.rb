# frozen_string_literal: true

module Mutations
  module Lookups
    # Modifies editable fields for a Tolerance
    class UpdateTolerance < UpdateLookupBaseMutation
      lookup_model Tolerance, type: Types::ToleranceType
    end
  end
end
