# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Cultivating Life Cycle Event
    class UpdateCultivatingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Cultivating Life Cycle Event'

      field :cultivating_event, Types::CultivatingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          cultivating_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
