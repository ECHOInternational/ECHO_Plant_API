# frozen_string_literal: true

module Types
  # Defines the Life Cycle Event Interface
  module LifeCycleEventType
    include Types::BaseInterface

    description 'Notation of Plant Lifecycle Events from planting to end-of-life'

    field :id, ID,
          null: false

    field :uuid, ID,
          description: 'The internal database ID for all life cycle events',
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
    definition_methods do # rubocop:disable all
      def resolve_type(object, _context) #rubocop:disable all
        case object
        when AcquireEvent
          Types::AcquireEventType
        when ThinningEvent
          Types::ThinningEventType
        when NutrientDeficiencyEvent
          Types::NutrientDeficiencyEventType
        when StakingEvent
          Types::StakingEventType
        when TrellisingEvent
          Types::TrellisingEventType
        when DiseaseEvent
          Types::DiseaseEventType
        when PestEvent
          Types::PestEventType
        when PruningEvent
          Types::PruningEventType
        when WeedManagementEvent
          Types::WeedManagementEventType
        when CultivatingEvent
          Types::CultivatingEventType
        when CompostingEvent
          Types::CompostingEventType
        when MulchingEvent
          Types::MulchingEventType
        when FertilizingEvent
          Types::FertilizingEventType
        when OtherEvent
          Types::OtherEventType
        when EndOfLifeEvent
          Types::EndOfLifeEventType
        when FloweringEvent
          Types::FloweringEventType
        when GerminationEvent
          Types::GerminationEventType
        when WeatherEvent
          Types::WeatherEventType
        when SoilPreparationEvent
          Types::SoilPreparationEventType
        when HarvestEvent
          Types::HarvestEventType
        when PlantingEvent
          Types::PlantingEventType
        when MovementEvent
          Types::MovementEventType
        else
          raise("Unexpected object: #{obj}")
        end
      end
    end
  end
end
