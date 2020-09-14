# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Movement Life Cycle Event
    class AddMovementLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Movement Life Cycle Event attached to the specified specimen'

      argument :location_id, ID,
               description: 'A location is an instance of a plant or a single group planting. See ID',
               required: true,
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

      def resolve(**attributes)
        event = MovementEvent.new(attributes)
        result = event.save
        errors = errors_from_active_record event.errors
        {
          movement_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
