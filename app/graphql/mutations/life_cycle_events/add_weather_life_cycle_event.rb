# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Weather Life Cycle Event
    class AddWeatherLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Weather Life Cycle Event attached to the specified specimen'

      argument :condition, Types::ConditionEnum,
               description: 'DESCRIPTION NEEDED',
               required: false

      field :weather_event, Types::WeatherEventType, null: true

      def resolve(specimen:, **attributes)
        event = WeatherEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          weather_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
