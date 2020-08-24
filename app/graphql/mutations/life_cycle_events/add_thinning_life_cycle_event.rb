# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Thinning Life Cycle Event
    class AddThinningLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Thinning Life Cycle Event attached to the specified specimen'

      field :thinning_event, Types::ThinningEventType, null: true

      def resolve(specimen:, **attributes)
        event = ThinningEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          thinning_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
