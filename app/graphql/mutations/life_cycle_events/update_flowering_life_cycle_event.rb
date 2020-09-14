# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Flowering Life Cycle Event
    class UpdateFloweringLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Flowering Life Cycle Event'

      argument :percent, Integer,
               description: 'Days to 50% flowering is determined by recording the number of days until 50% of plants in a plot had at least one open flower',
               required: false

      field :flowering_event, Types::FloweringEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          flowering_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
