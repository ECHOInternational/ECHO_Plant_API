# frozen_string_literal: true

module Types
  # Defines the Life Cycle Event Interface
  module LifeCycleEventType
    include Types::BaseInterface

    description 'DESCRIPTION NEEDED'

    field :id, ID,
          null: false

    field :uuid, ID,
          description: 'The internal database ID for al life cycle event',
          null: false,
          method: :id

    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a life cycle event',
          null: true

    field :notes, String,
          description: 'Full text notes for a life cycle event',
          null: true

    field :specimen, Types::SpecimenType,
          description: 'The Specimen to which this life cycle event belongs',
          null: false

    field :datetime, GraphQL::Types::ISO8601DateTime,
          description: 'The date and time that the life cycle event took place',
          null: false
    definition_methods do
      def resolve_type(object, _context)
        case object
        when AcquireEvent
          Types::AcquireEventType
        when ThinningEvent
          Types::ThinningEventType
        when NutrientDeficiencyEvent
          Types::NutrientDeficiencyEventType
        when StakingEvent
          Types::StakingEventType
        else
          raise("Unexpected object: #{obj}")
        end
      end
    end
  end
end
