# frozen_string_literal: true

# Relation table for GrowthHabits and Varieties
class GrowthHabitsVariety < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :growth_habit
  belongs_to :variety

  versioned_under_root { ['Variety', variety_id] }
end
