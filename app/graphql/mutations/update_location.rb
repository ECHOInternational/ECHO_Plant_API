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
      coord_errors = apply_coordinates(location, attributes)
      return { location: location, errors: coord_errors } if coord_errors

      location.update(attributes)
      { location: location, errors: errors_from_active_record(location.errors) }
    end

    private

    def explicit_nil?(attributes, key)
      attributes.key?(key) && attributes[key].nil?
    end

    def apply_coordinates(location, attributes)
      lat_nil = explicit_nil?(attributes, :latitude)
      lng_nil = explicit_nil?(attributes, :longitude)
      return unless lat_nil || lng_nil

      return clear_coordinates(location, attributes) if lat_nil && lng_nil

      nil_field = lat_nil ? 'latitude' : 'longitude'
      [{ field: nil_field, message: 'latitude and longitude must be provided together', code: 400 }]
    end

    def clear_coordinates(location, attributes)
      attributes.delete(:latitude)
      attributes.delete(:longitude)
      location.latlng = nil
      nil
    end
  end
end
