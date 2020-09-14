# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Updates a Update Acquire Life Cycle Event
    class UpdateAcquireLifeCycleEvent < UpdateLifeCycleEventBaseMutation
      description 'Updates an Acquire Life Cycle Event'

      argument :condition, Types::ConditionEnum,
               description: 'Describes the quality or condition of germplasm on receipt - good,fair,poor',
               required: false

      argument :accession, String,
               description: 'Accession is a group of related plant material from a single species which is collected at one time from a specific location',
               required: false

      argument :source, String,
               description: 'Where did the germplasm come from (ECHO Florida,ECHO Asia,ECHO Tanzania,Other',
               required: false

      field :acquire_event, Types::AcquireEventType, null: true

      def resolve(life_cycle_event:, **attributes)
        life_cycle_event.update(attributes)
        errors = errors_from_active_record life_cycle_event.errors
        {
          acquire_event: life_cycle_event,
          errors: errors
        }
      end
    end
  end
end
