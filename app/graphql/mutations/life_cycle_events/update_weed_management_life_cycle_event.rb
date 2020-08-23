# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Weed Management Life Cycle Event
    class UpdateWeedManagementLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Weed Management Life Cycle Event'

      field :weed_management_event, Types::WeedManagementEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          weed_management_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
