# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Fertilizing Life Cycle Event
    class UpdateFertilizingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Fertilizing Life Cycle Event'

      field :fertilizing_event, Types::FertilizingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          fertilizing_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
