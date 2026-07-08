# frozen_string_literal: true

module Mutations
  module Relations
    # Replaces the set of growth habits linked to a variety
    class UpdateVarietyGrowthHabits < UpdateRelationsBaseMutation
      relates Variety, type: Types::VarietyType, association: :growth_habits, items_type: Types::GrowthHabitType
    end
  end
end
