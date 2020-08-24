# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Nutrient Deficiency Life Cycle Event
    class UpdateNutrientDeficiencyLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Nutrient Deficiency Life Cycle Event'

      field :nutrient_deficiency_event, Types::NutrientDeficiencyEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          nutrient_deficiency_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
