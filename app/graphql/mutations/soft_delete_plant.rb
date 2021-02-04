# frozen_string_literal: true

module Mutations
  # Soft Deletes a Plant
  class SoftDeletePlant < BaseMutation
    argument :plant_id, ID,
             description: 'The plant to be soft deleted.',
             required: true,
             loads: Types::PlantType
    argument :force, Boolean,
             description: 'Forces the plant to be soft deleted, even if required related records (which have not also been soft deleted) exist.',
             required: false

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **_attributes)
      authorize plant, :update?
    end

    def visible_dependency_errors(plant)
      dependency_errors = []

      plant.specimens.each do | specimen |
        if specimen.visibility != "deleted"
          specimen_api_id = PlantApiSchema.id_from_object(specimen, Specimen, nil)
          dependency_errors << {
            field: "plantId",
            message: "record cannot be soft deleted because it is related to active specimen: #{specimen_api_id}. Use 'force' parameter to overrride.",
            code: 400,
            value: specimen_api_id
          }
        end
      end
      plant.varieties.each do | variety |
        if variety.visibility != "deleted"
          variety_api_id = PlantApiSchema.id_from_object(variety, Variety, nil)
          dependency_errors << {
            field: "plantId",
            message: "record cannot be soft deleted because it is related to active variety: #{variety_api_id}. Use 'force' parameter to overrride.",
            code: 400,
            value: variety_api_id
          }
        end
      end

      dependency_errors
    end

    def resolve(plant:, force: false, **_attributes)
      id = PlantApiSchema.id_from_object(plant, Plant, {})
      dependency_errors = visible_dependency_errors(plant)
      
      if force == true || dependency_errors.empty?
        plant.update(visibility: :deleted)
      end
      
      errors = errors_from_active_record(plant.errors) + dependency_errors
      
      {
        plant: plant,
        errors: errors
      }
    end
  end
end
