# frozen_string_literal: true

# Lifecycle Event MovementEvent
class MovementEvent < LifeCycleEvent
  # Automatically inherits all methods and properties from LifeCycleEvent
  validates :location, presence: true
end
