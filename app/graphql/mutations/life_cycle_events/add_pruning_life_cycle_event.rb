# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Pruning Life Cycle Event
    class AddPruningLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Pruning Life Cycle Event attached to the specified specimen'

      field :pruning_event, Types::PruningEventType, null: true

      def resolve(specimen:, **attributes)
        event = PruningEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          pruning_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
