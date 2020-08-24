# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Composting Life Cycle Event
    class UpdateCompostingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Composting Life Cycle Event'

      field :composting_event, Types::CompostingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          composting_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
