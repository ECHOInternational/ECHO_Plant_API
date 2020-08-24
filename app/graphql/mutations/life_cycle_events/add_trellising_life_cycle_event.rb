# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Trellising Life Cycle Event
    class AddTrellisingLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Trellising Life Cycle Event attached to the specified specimen'

      field :trellising_event, Types::TrellisingEventType, null: true

      def resolve(specimen:, **attributes)
        event = TrellisingEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          trellising_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
