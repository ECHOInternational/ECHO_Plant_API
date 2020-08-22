# frozen_string_literal: true

module Mutations
  module LifeCycleEvents
    # Base Class for creating Life Cycle Events
    class CreateLifeCycleEventBaseMutation < BaseMutation

      argument :specimen_id, ID,
               required: true,
               description: 'The specimen to which this life cycle event should be added',
               loads: Types::SpecimenType
      argument :datetime, GraphQL::Types::ISO8601DateTime,
               description: 'The date and time that the life cycle event took place',
               required: true
      argument :notes, String,
               description: 'Full text notes for a life cycle event',
               required: false

      field :errors, [Types::MutationError], null: false

      def authorized?(specimen:, **_attributes)
        authorize specimen, :update?
      end
    end
  end
end
