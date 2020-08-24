# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Creates a Add Staking Life Cycle Event
    class AddStakingLifeCycleEvent < CreateLifeCycleEventBaseMutation
      description 'Creates a Staking Life Cycle Event attached to the specified specimen'

      field :staking_event, Types::StakingEventType, null: true

      def resolve(specimen:, **attributes)
        event = StakingEvent.new(attributes)
        event.specimen = specimen
        result = event.save
        errors = errors_from_active_record event.errors
        {
          staking_event: result ? event : nil,
          errors: errors
        }
      end
    end
  end
end
