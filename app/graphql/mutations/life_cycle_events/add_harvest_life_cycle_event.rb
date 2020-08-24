# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Harvest Life Cycle Event
    class AddHarvestLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Harvest Life Cycle Event attached to the specified specimen'

      argument :quantity, Float,
               description: 'DESCRIPTION NEEDED',
               required: true

      argument :unit, Types::UnitEnum,
               description: 'DESCRIPTION NEEDED',
               required: true

      argument :quality, Integer,
               description: 'DESCRIPTION NEEDED',
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
