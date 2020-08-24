# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add End Of Life Life Cycle Event
    class AddEndOfLifeLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a End Of Life Life Cycle Event attached to the specified specimen'

      field :end_of_life_event, Types::EndOfLifeEventType, null: true

      def resolve(specimen:, **attributes)
        event = EndOfLifeEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          end_of_life_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
