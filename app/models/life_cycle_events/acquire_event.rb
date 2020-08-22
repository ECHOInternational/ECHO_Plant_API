# frozen_string_literal: true

# Lifecycle Event AcquireEvent
class AcquireEvent < LifeCycleEvent
  # Automatically inherits all methods and properties from LifeCycleEvent
  validates :condition, :source, presence: true
end
