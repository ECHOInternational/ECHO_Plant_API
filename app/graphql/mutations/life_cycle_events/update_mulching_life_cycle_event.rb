# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Mulching Life Cycle Event
    class UpdateMulchingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Mulching Life Cycle Event'

      field :mulching_event, Types::MulchingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          mulching_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
