# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Pest Life Cycle Event
    class UpdatePestLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Pest Life Cycle Event'

      field :pest_event, Types::PestEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          pest_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
