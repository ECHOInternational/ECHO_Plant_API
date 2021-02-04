# frozen_string_literal: true

module Mutations
  # Soft Deletes a Location
  class SoftDeleteLocation < BaseMutation
    argument :location_id, ID,
             description: 'The location to be soft deleted.',
             required: true,
             loads: Types::LocationType
    argument :force, Boolean,
             description: 'Forces the location to be soft deleted, even if required related records (which have not also been soft deleted) exist.',
             required: false


    field :location, Types::LocationType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(location:, **_attributes)
      authorize location, :update?
    end

    def visible_dependency_errors(location)
      dependency_errors = []
      return dependency_errors if location.life_cycle_events.count == 0

      location.life_cycle_events.each do | life_cycle_event |
        if life_cycle_event.deleted != true

          # Allow delete if record is orphaned
          next unless life_cycle_event.specimen
          # Allow delete if record's specimen is itself soft-deleted
          next if life_cycle_event.specimen.visibility == "deleted"

          lce_api_id = PlantApiSchema.id_from_object(life_cycle_event, life_cycle_event.class, nil)

          dependency_errors << {
            field: "locationId",
            message: "record cannot be soft deleted because it is related to active life_cyle_event: #{life_cycle_event.class} #{lce_api_id}. Use 'force' parameter to overrride.",
            code: 400,
            value: lce_api_id
          }
        end
      end
      dependency_errors
    end

    def resolve(location:, force: false, **_attributes)
      id = PlantApiSchema.id_from_object(location, Location, {})
      dependency_errors = visible_dependency_errors(location)
      
      if force == true || dependency_errors.empty?
        location.update(visibility: :deleted)
      end
      
      errors = errors_from_active_record(location.errors) + dependency_errors
      
      {
        location: location,
        errors: errors
      }
    end
  end
end
