# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of tolerances linked to a plant
    class UpdatePlantTolerances < UpdateRelationsBaseMutation
      relates Plant, type: Types::PlantType, association: :tolerances, items_type: Types::ToleranceType
    end
  end
end
