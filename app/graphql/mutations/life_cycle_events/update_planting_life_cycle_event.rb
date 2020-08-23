# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Planting Life Cycle Event
    class UpdatePlantingLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Planting Life Cycle Event'

      argument :location_id, ID,
               description: 'DESCRIPTION NEEDED',
               required: false,
               loads: Types::LocationType

      argument :quantity, Float,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :unit, Types::UnitEnum,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :between_row_spacing, Integer,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :in_row_spacing, Integer,
               description: 'DESCRIPTION NEEDED',
               required: false

      field :planting_event, Types::PlantingEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          planting_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
