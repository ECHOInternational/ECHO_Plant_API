# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update End Of Life Life Cycle Event
    class UpdateEndOfLifeLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a End Of Life Life Cycle Event'

      field :end_of_life_event, Types::EndOfLifeEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          end_of_life_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
