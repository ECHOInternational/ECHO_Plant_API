# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of antinutrients linked to a plant
    class UpdatePlantAntinutrients < UpdateRelationsBaseMutation
      relates Plant, type: Types::PlantType, association: :antinutrients, items_type: Types::AntinutrientType
    end
  end
end
