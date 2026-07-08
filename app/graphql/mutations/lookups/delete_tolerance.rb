# frozen_string_literal: true

module Mutations
  module Lookups
    # Deletes a Tolerance
    class DeleteTolerance < DeleteLookupBaseMutation
      lookup_model Tolerance, type: Types::ToleranceType
    end
  end
end
