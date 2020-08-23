# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Disease Life Cycle Event
    class AddDiseaseLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Disease Life Cycle Event attached to the specified specimen'

      field :disease_event, Types::DiseaseEventType, null: true

      def resolve(specimen:, **attributes)
        event = DiseaseEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          disease_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
