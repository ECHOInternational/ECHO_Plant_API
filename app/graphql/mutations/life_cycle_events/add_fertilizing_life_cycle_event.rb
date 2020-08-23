# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Fertilizing Life Cycle Event
    class AddFertilizingLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Fertilizing Life Cycle Event attached to the specified specimen'

      field :fertilizing_event, Types::FertilizingEventType, null: true

      def resolve(specimen:, **attributes)
        event = FertilizingEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          fertilizing_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
