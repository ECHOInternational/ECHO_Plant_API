# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of tolerances linked to a variety
    class UpdateVarietyTolerances < UpdateRelationsBaseMutation
      relates Variety, type: Types::VarietyType, association: :tolerances, items_type: Types::ToleranceType
    end
  end
end
