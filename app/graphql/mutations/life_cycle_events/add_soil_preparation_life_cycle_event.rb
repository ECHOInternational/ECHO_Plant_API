# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Soil Preparation Life Cycle Event
    class AddSoilPreparationLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Soil Preparation Life Cycle Event attached to the specified specimen'

      argument :soil_preparation, Types::SoilPreparationEnum,
               description: 'DESCRIPTION NEEDED',
               required: true

      field :soil_preparation_event, Types::SoilPreparationEventType, null: true

      def resolve(specimen:, **attributes)
        event = SoilPreparationEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          soil_preparation_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
