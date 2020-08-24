# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Germination Life Cycle Event
    class AddGerminationLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Germination Life Cycle Event attached to the specified specimen'

      argument :percent, Integer,
               description: 'DESCRIPTION NEEDED',
               required: false

      argument :quality, Integer,
               description: 'DESCRIPTION NEEDED',
               required: false

      field :germination_event, Types::GerminationEventType, null: true

      def resolve(specimen:, **attributes)
        event = GerminationEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          germination_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
