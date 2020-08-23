# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Soil Preparation Life Cycle Event
    class UpdateSoilPreparationLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Soil Preparation Life Cycle Event'

      argument :soil_preparation, Types::SoilPreparationEnum,
               description: 'DESCRIPTION NEEDED',
               required: false

      field :soil_preparation_event, Types::SoilPreparationEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          soil_preparation_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
