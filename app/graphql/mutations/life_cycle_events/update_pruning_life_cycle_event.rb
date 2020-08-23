# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Pruning Life Cycle Event
    class UpdatePruningLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Pruning Life Cycle Event'

      field :pruning_event, Types::PruningEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          pruning_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
