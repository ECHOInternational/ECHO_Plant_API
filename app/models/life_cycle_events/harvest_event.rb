# frozen_string_literal: true

# Lifecycle Event HarvestEvent
class HarvestEvent < LifeCycleEvent
  # Automatically inherits all methods and properties from LifeCycleEvent
  validates :quantity, :unit, :quality, presence: true
end
