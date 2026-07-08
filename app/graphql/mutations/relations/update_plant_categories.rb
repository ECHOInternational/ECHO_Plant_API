# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of categories linked to a plant
    class UpdatePlantCategories < UpdateRelationsBaseMutation
      relates Plant, type: Types::PlantType, association: :categories, items_type: Types::CategoryType
    end
  end
end
