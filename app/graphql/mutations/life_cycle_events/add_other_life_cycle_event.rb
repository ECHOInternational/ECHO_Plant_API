# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Other Life Cycle Event
    class AddOtherLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Other Life Cycle Event attached to the specified specimen'

      field :other_event, Types::OtherEventType, null: true

      def resolve(specimen:, **attributes)
        event = OtherEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          other_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
