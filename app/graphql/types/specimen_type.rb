# frozen_string_literal: true

module Types
  # Defines fields for a specimen - categories contains a group of plant objects
  class SpecimenType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A specimen is an instance of a plant or a single group planting.'

    field :uuid, ID,
          description: 'The internal database ID for a specimen',
          null: false, method: :id
    field :name, String,
          description: 'The user assigned name of a specimen',
          null: true
    field :created_by, String,
          description: "The user ID of a specimen's creator",
          null: true
    field :owned_by, String,
          description: "The user ID of a specimen's owner",
          null: true
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a specimen',
          null: true
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the specimen. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false
    field :plant, Types::PlantType,
          description: 'The kind of plant this specimen is',
          null: false
    field :variety, Types::VarietyType,
          description: 'The variety of plant this specimen is',
          null: true
    field :terminated, Boolean,
          description: 'Indicates whether or not this plant is still growing',
          null: false
    field :successful, Boolean,
          description: 'Indicates if the user believes this was successful',
          null: true
    field :recommended, Boolean,
          description: 'Indicates if the user would recommend this to others',
          null: true
    field :saved_seed, Boolean,
          description: 'Indicates if the user saved seeds collected from this specimen',
          null: true
    field :will_share_seed, Boolean,
          description: 'Indicates if the user plans to share seeds collected from this specimen',
          null: true
    field :will_plant_again, Boolean,
          description: 'Indicates if the user plans to plant this again',
          null: true
    field :notes, String,
          description: 'User supplied notes about the experience with this specimen',
          null: true
    field :life_cycle_events, Types::LifeCycleEventType::LifeCycleEventConnectionWithTotalCountType,
          description: 'A list of life cycle events for this specimen, ordered by date ascending',
          null: true,
          connection: true

    def life_cycle_events
      @object.life_cycle_events.order(datetime: :asc)
    end

    def images
      Pundit.policy_scope(context[:current_user], @object.images)
    end

    def visibility
      @object.visibility.to_sym
    end

    # def versions
    # @object.translation.versions.where(event: "update").reorder('created_at DESC')
    # end
  end
end
