# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Germination Life Cycle Event
    class UpdateGerminationLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates a Germination Life Cycle Event'

      argument :percent, Integer,
               description: 'Germination percentage is an estimate of the viability of a population of seeds',
               required: false

      argument :quality, Integer,
               description: 'Rate 1-10, 10 best',
               required: false

      field :germination_event, Types::GerminationEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          germination_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
