# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Base Class for Updating Life Cycle Events
    class UpdateLifeCycleEventBaseMutation < BaseMutation
      argument :life_cycle_event_id, ID,
               required: true,
               description: 'The life cycle event to update',
               loads: Types::LifeCycleEventType
      argument :datetime, GraphQL::Types::ISO8601DateTime,
               description: 'The date and time that the life cycle event took place',
               required: false
      argument :notes, String,
               description: 'Full text notes for a life cycle event',
               required: false

      field :errors, [Types::MutationError], null: false

      def authorized?(life_cycle_event:, **_attributes)
        authorize life_cycle_event.specimen, :update?
      end
    end
  end
end
