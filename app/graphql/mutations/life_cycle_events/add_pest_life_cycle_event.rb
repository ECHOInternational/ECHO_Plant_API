# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Pest Life Cycle Event
    class AddPestLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Pest Life Cycle Event attached to the specified specimen'

      field :pest_event, Types::PestEventType, null: true

      def resolve(specimen:, **attributes)
        event = PestEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          pest_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
