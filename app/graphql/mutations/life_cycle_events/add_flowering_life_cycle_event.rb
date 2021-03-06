# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Flowering Life Cycle Event
    class AddFloweringLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Flowering Life Cycle Event attached to the specified specimen'

      argument :percent, Integer,
               description: 'Days to 50% flowering is determined by recording the number of days until 50% of plants in a plot had at least one open flower',
               required: false

      field :flowering_event, Types::FloweringEventType, null: true

      def resolve(specimen:, **attributes)
        event = FloweringEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          flowering_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
