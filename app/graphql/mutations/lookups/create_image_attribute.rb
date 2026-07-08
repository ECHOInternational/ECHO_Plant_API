# frozen_string_literal: true

module Mutations
  module Lookups
    # Creates an ImageAttribute
    class CreateImageAttribute < CreateLookupBaseMutation
      lookup_model ImageAttribute, type: Types::ImageAttributeType
    end
  end
end
