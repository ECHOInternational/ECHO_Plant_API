# frozen_string_literal: true

module Mutations
  module Lookups
    # Modifies editable fields for an ImageAttribute
    class UpdateImageAttribute < UpdateLookupBaseMutation
      lookup_model ImageAttribute, type: Types::ImageAttributeType
    end
  end
end
