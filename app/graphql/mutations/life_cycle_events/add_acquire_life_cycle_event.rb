# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Acquire Life Cycle Event
    class AddAcquireLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Acquire Life Cycle Event attached to the specified specimen'

      argument :condition, Types::ConditionEnum,
               description: 'Describes the quality or condition of the germplasm on receipt - good,fair,poor',
               required: true

      argument :accession, String,
               description: 'An accession is a group of related plant material from a single species which is collected at one time from a specific location',
               required: false

      argument :source, String,
               description: 'Where was the germplasm ordered from (ECHO Florida,ECHO Asia,ECHO Tanzania,Other)',
               required: true

      field :acquire_event, Types::AcquireEventType, null: true

      def resolve(specimen:, **attributes)
        event = AcquireEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          acquire_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
