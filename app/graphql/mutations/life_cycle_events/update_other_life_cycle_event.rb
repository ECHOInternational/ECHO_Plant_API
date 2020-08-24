# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Other Life Cycle Event
    class UpdateOtherLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Other Life Cycle Event'

      field :other_event, Types::OtherEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          other_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
