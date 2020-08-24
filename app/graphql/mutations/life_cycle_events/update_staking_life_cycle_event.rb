# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Staking Life Cycle Event
    class UpdateStakingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Staking Life Cycle Event'

      field :staking_event, Types::StakingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          staking_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
