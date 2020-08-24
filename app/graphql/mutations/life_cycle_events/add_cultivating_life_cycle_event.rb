# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Cultivating Life Cycle Event
    class AddCultivatingLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Cultivating Life Cycle Event attached to the specified specimen'

      field :cultivating_event, Types::CultivatingEventType, null: true

      def resolve(specimen:, **attributes)
        event = CultivatingEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          cultivating_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
