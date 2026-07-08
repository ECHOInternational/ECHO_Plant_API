# frozen_string_literal: true

module Mutations
  module Lookups
    # Modifies editable fields for an Antinutrient
    class UpdateAntinutrient < UpdateLookupBaseMutation
      lookup_model Antinutrient, type: Types::AntinutrientType
    end
  end
end
