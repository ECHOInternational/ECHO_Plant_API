# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of antinutrients linked to a variety
    class UpdateVarietyAntinutrients < UpdateRelationsBaseMutation
      relates Variety, type: Types::VarietyType, association: :antinutrients, items_type: Types::AntinutrientType
    end
  end
end
