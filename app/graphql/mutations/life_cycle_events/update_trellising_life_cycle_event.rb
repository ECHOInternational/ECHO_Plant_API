# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Trellising Life Cycle Event
    class UpdateTrellisingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Trellising Life Cycle Event'

      field :trellising_event, Types::TrellisingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          trellising_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
