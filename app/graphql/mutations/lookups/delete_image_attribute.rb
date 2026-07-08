# frozen_string_literal: true

module Mutations
  module Lookups
    # Deletes an ImageAttribute
    class DeleteImageAttribute < DeleteLookupBaseMutation
      lookup_model ImageAttribute, type: Types::ImageAttributeType
    end
  end
end
