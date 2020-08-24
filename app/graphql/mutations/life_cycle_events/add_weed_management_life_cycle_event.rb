# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Weed Management Life Cycle Event
    class AddWeedManagementLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Weed Management Life Cycle Event attached to the specified specimen'

      field :weed_management_event, Types::WeedManagementEventType, null: true

      def resolve(specimen:, **attributes)
        event = WeedManagementEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          weed_management_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
