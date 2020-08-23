# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Movement Life Cycle Event
    class AddMovementLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Movement Life Cycle Event attached to the specified specimen'

      argument :location_id, ID,
               description: 'DESCRIPTION NEEDED',
               required: true,
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
