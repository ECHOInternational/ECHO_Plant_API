# frozen_string_literal: true

# Relation table for GrowthHabits and Plants
class GrowthHabitsPlant < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :growth_habit
  belongs_to :plant

  versioned_under_root { ['Plant', plant_id] }
end
