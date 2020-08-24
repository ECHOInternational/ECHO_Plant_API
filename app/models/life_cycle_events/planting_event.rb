# frozen_string_literal: true

# Lifecycle Event PlantingEvent
class PlantingEvent < LifeCycleEvent
  # Automatically inherits all methods and properties from LifeCycleEvent
  validates :location, presence: true
end
