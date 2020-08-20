# frozen_string_literal: true

module Mutations
  # Creates a Location
  class CreateLocation < BaseMutation
    argument :name, String,
             required: true,
             description: 'The name of the location'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the location'
    argument :soil_quality, Types::SoilQualityEnum,
             description: 'The general soil quality at the location',
             required: false
    argument :latitude, Float,
             description: 'The latitude of the location',
             required: false
    argument :longitude, Float,
             description: 'The longitude of the location',
             required: false
    argument :area, Float,
             description: 'The total size of the location in hectares',
             required: false
    argument :slope, Int,
             description: 'The slope of the land in degrees of the location',
             required: false
    argument :altitude, Int,
             description: 'The altitude in meters of the location',
             required: false
    argument :average_rainfall, Int,
             description: 'The average rainfall in mm of the location',
             required: false
    argument :average_temperature, Int,
             description: 'The average temperature in degrees celsius of the location',
             required: false
    argument :irrigated, Boolean,
             description: 'Indicates whether the location is irrigated',
             required: false
    argument :notes, String,
             description: 'Description and notes about the location',
             required: false

    field :location, Types::LocationType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      authorize Location, :create?
    end

    def resolve(**attributes)
      attributes
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)

      location = Location.new(attributes)
      result = location.save
      errors = errors_from_active_record location.errors
      {
        location: result ? location : nil,
        errors: errors
      }
    end
  end
end
