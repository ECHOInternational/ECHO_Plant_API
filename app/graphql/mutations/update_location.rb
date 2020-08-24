# frozen_string_literal: true

module Mutations
  # Updates a Location
  class UpdateLocation < BaseMutation
    argument :location_id, ID, required: true, loads: Types::LocationType

    argument :name, String,
             required: false,
             description: 'The name of the location'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the location'
    argument :soil_quality, Types::ConditionEnum,
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

    def authorized?(location:, **_attributes)
      authorize location, :update?
    end

    def resolve(location:, **attributes)
      location.update(attributes)
      errors = errors_from_active_record location.errors
      {
        location: location,
        errors: errors
      }
    end
  end
end
