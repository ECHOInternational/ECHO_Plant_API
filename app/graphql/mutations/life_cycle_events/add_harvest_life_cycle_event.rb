# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Harvest Life Cycle Event
    class AddHarvestLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Harvest Life Cycle Event attached to the specified specimen'

      argument :quantity, Float,
               description: 'Total harvest units for a single harvest event - may be multiple harvest events',
               required: true

      argument :unit, Types::UnitEnum,
               description: 'Indicates the unit of associated value (Weight in kg,Count)',
               required: true

      argument :quality, Integer,
               description: 'Rate 1-10, 10 best',
               required: true

      field :harvest_event, Types::HarvestEventType, null: true

      def resolve(specimen:, **attributes)
        event = HarvestEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          harvest_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
