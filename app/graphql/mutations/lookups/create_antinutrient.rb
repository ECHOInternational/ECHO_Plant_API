# frozen_string_literal: true

module Mutations
  module Lookups
    # Creates an Antinutrient
    class CreateAntinutrient < CreateLookupBaseMutation
      lookup_model Antinutrient, type: Types::AntinutrientType
    end
  end
end
