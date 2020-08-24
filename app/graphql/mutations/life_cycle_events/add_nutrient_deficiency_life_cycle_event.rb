# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Nutrient Deficiency Life Cycle Event
    class AddNutrientDeficiencyLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Nutrient Deficiency Life Cycle Event attached to the specified specimen'

      field :nutrient_deficiency_event, Types::NutrientDeficiencyEventType, null: true

      def resolve(specimen:, **attributes)
        event = NutrientDeficiencyEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          nutrient_deficiency_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
