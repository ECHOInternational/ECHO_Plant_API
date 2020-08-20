# frozen_string_literal: true

module Types
  # Defines fields for a location - categories contains a group of plant objects
  class LocationType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A location is an instance of a plant or a single group planting.'

    field :uuid, ID,
          description: 'The internal database ID for a location',
          null: false,
          method: :id
    field :name, String,
          description: 'The user assigned name of a location',
          null: false
    field :created_by, String,
          description: "The user ID of a location's creator",
          null: true
    field :owned_by, String,
          description: "The user ID of a location's owner",
          null: true
    field :images, Types::ImageType.connection_type,
          description: 'A list of images related to a location',
          null: true
    field :visibility, Types::VisibilityEnum,
          description: 'The visibility of the location. Can be: PUBLIC, PRIVATE, DRAFT, DELETED',
          null: false
    field :soil_quality, Types::SoilQualityEnum,
          description: 'The general soil quality at the location',
          null: true
    field :latitude, Float,
          description: 'The latitude of the location',
          null: true
    field :longitude, Float,
          description: 'The longitude of the location',
          null: true
    field :area, Float,
          description: 'The total size of the location in hectares',
          null: true
    field :slope, Int,
          description: 'The slope of the land in degrees of the location',
          null: true
    field :altitude, Int,
          description: 'The altitude in meters of the location',
          null: true
    field :average_rainfall, Int,
          description: 'The average rainfall in mm of the location',
          null: true
    field :average_temperature, Int,
          description: 'The average temperature in degrees celsius of the location',
          null: true
    field :irrigated, Boolean,
          description: 'Indicates whether the location is irrigated',
          null: false
    field :notes, String,
          description: 'Description and notes about the location',
          null: true

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
