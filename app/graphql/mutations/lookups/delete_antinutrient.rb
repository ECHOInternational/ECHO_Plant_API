# frozen_string_literal: true

module Mutations
  module Lookups
    # Deletes an Antinutrient
    class DeleteAntinutrient < DeleteLookupBaseMutation
      lookup_model Antinutrient, type: Types::AntinutrientType
    end
  end
end
