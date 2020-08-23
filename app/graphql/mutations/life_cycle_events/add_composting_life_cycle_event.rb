# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Composting Life Cycle Event
    class AddCompostingLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Composting Life Cycle Event attached to the specified specimen'

      field :composting_event, Types::CompostingEventType, null: true

      def resolve(specimen:, **attributes)
        event = CompostingEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          composting_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
