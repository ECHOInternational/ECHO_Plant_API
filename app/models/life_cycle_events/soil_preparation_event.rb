# frozen_string_literal: true

# Lifecycle Event SoilPreparationEvent
class SoilPreparationEvent < LifeCycleEvent
  # Automatically inherits all methods and properties from LifeCycleEvent
  validates :soil_preparation, presence: true
end
