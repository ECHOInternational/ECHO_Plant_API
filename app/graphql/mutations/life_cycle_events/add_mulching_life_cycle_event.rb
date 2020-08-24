# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Mulching Life Cycle Event
    class AddMulchingLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Mulching Life Cycle Event attached to the specified specimen'

      field :mulching_event, Types::MulchingEventType, null: true

      def resolve(specimen:, **attributes)
        event = MulchingEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          mulching_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
