# frozen_string_literal: true

module Mutations
  module Lookups
    # Creates a GrowthHabit
    class CreateGrowthHabit < CreateLookupBaseMutation
      lookup_model GrowthHabit, type: Types::GrowthHabitType
    end
  end
end
