# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Acquire Life Cycle Event
    class UpdateAcquireLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Acquire Life Cycle Event'

      argument :condition, Types::ConditionEnum,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :accession, String,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :source, String,
               description: 'DESCRIPTION NEEDED',
               required: false

      field :acquire_event, Types::AcquireEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          acquire_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
