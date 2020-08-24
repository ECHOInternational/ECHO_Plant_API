# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Thinning Life Cycle Event
    class UpdateThinningLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Thinning Life Cycle Event'

      field :thinning_event, Types::ThinningEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          thinning_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
