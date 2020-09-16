# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Movement Life Cycle Event
    class UpdateMovementLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Movement Life Cycle Event'

      argument :location_id, ID,
               description: 'A location is an instance of a plant or a single group planting. See ID',
               required: false,
               loads: Types::LocationType

      argument :quantity, Float,
               description: '# of plants moved (transplanted)',
               required: false

      argument :unit, Types::UnitEnum,
               description: 'Count or Weight(kg)',
               required: false

      argument :between_row_spacing, Integer,
               description: 'cm between rows',
               required: false

      argument :in_row_spacing, Integer,
               description: 'cm spacing between plants',
               required: false

      field :movement_event, Types::MovementEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          movement_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
