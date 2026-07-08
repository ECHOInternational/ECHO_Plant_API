# frozen_string_literal: true

module Mutations
  module Lookups
    # Modifies editable fields for a GrowthHabit
    class UpdateGrowthHabit < UpdateLookupBaseMutation
      lookup_model GrowthHabit, type: Types::GrowthHabitType
    end
  end
end
