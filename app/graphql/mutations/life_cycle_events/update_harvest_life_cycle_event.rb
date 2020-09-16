# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Harvest Life Cycle Event
    class UpdateHarvestLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Harvest Life Cycle Event'

      argument :quantity, Float,
               description: 'Total harvest units for a single harvest event - may be multiple harvest events',
               required: false

      argument :unit, Types::UnitEnum,
               description: 'Indicates the unit of associated value (Weight in kg,Count)',
               required: false

      argument :quality, Integer,
               description: 'Rate 1-10, 10 best',
               required: false

      field :harvest_event, Types::HarvestEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          harvest_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
