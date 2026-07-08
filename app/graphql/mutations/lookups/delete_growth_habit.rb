# frozen_string_literal: true

module Mutations
  module Lookups
    # Deletes a GrowthHabit
    class DeleteGrowthHabit < DeleteLookupBaseMutation
      lookup_model GrowthHabit, type: Types::GrowthHabitType
    end
  end
end
