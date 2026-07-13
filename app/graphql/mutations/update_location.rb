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
    argument :publication_state, Types::PublicationStateEnum,
             required: false,
             description: 'New publication state (DRAFT or PUBLISHED).'
    argument :access_level, Types::AccessLevelEnum,
             required: false,
             description: 'New access level (ORGANIZATION or PUBLIC).'

    field :location, Types::LocationType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(location:, **attributes)
      authorize location, :update?
      authorize_visibility_transition(location, attributes[:visibility])
      true
    end

    def resolve(location:, **attributes)
      if attributes.key?(:visibility)
        Rails.logger.info(
          "legacy_contract.visibility_arg mutation=UpdateLocation location_id=#{location.id}"
        )
      end

      # When transitioning to deleted, stamp deleted_by_principal_id.
      vis = attributes[:visibility]
      if vis && vis.to_s.casecmp('deleted').zero? && location.visibility.to_s != 'deleted'
        attributes[:deleted_by_principal_id] = context[:current_user]&.principal&.id
      end

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
