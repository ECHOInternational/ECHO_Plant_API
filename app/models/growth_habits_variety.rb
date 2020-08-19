# frozen_string_literal: true

# Relation table for GrowthHabits and Varieties
class GrowthHabitsVariety < ApplicationRecord
  belongs_to :growth_habit
  belongs_to :variety
end
