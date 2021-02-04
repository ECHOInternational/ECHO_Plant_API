# frozen_string_literal: true

module Mutations
  # Soft Deletes a Variety
  class SoftDeleteVariety < BaseMutation
    argument :variety_id, ID,
             description: 'The variety to be soft deleted.',
             required: true,
             loads: Types::VarietyType
    argument :force, Boolean,
             description: 'Forces the variety to be soft deleted, even if required related records (which have not also been soft deleted) exist.',
             required: false


    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(variety:, **_attributes)
      authorize variety, :update?
    end

    def visible_dependency_errors(variety)
      dependency_errors = []
      return dependency_errors if variety.specimens.count == 0

      variety.specimens.each do | specimen |
        if specimen.visibility != "deleted"
          specimen_api_id = PlantApiSchema.id_from_object(specimen, Specimen, nil)
          dependency_errors << {
            field: "varietyId",
            message: "record cannot be soft deleted because it is related to active specimen: #{specimen_api_id}. Use 'force' parameter to overrride.",
            code: 400,
            value: specimen_api_id
          }
        end
      end
      dependency_errors
    end

    def resolve(variety:, force: false, **_attributes)
      id = PlantApiSchema.id_from_object(variety, Variety, {})
      dependency_errors = visible_dependency_errors(variety)
      
      if force == true || dependency_errors.empty?
        variety.update(visibility: :deleted)
      end
      
      errors = errors_from_active_record(variety.errors) + dependency_errors
      
      {
        variety: variety,
        errors: errors
      }
    end
  end
end
