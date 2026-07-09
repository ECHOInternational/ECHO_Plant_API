# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of growth habits linked to a plant
    class UpdatePlantGrowthHabits < UpdateRelationsBaseMutation
      relates Plant, type: Types::PlantType, association: :growth_habits, items_type: Types::GrowthHabitType
    end
  end
end
