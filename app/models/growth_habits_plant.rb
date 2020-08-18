# frozen_string_literal: true

# Relation table for GrowthHabits and Plants
class GrowthHabitsPlant < ApplicationRecord
  belongs_to :growth_habit
  belongs_to :plant
end
