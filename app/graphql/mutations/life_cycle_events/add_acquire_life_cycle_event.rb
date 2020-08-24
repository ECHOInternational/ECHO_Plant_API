# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Acquire Life Cycle Event
    class AddAcquireLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Acquire Life Cycle Event attached to the specified specimen'

      argument :condition, Types::ConditionEnum,
               description: 'DESCRIPTION NEEDED',
               required: true

      argument :accession, String,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :source, String,
               description: 'DESCRIPTION NEEDED',
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
