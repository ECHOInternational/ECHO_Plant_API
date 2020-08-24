# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Disease Life Cycle Event
    class UpdateDiseaseLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Disease Life Cycle Event'

      field :disease_event, Types::DiseaseEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          disease_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
