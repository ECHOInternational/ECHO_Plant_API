# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Weather Life Cycle Event
    class UpdateWeatherLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Weather Life Cycle Event'

      argument :condition, Types::ConditionEnum,
               description: 'Describe unique weather conditions affecting plants or planting',
               required: false

      field :weather_event, Types::WeatherEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          weather_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
