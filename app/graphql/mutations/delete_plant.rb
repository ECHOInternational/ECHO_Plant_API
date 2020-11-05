# frozen_string_literal: true

module Mutations
  # Deletes a Plant
  class DeletePlant < BaseMutation
    argument :plant_id, ID,
             description: 'The plant to be deleted',
             required: true,
             loads: Types::PlantType

    field :plant_id, ID, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **_attributes)
      authorize plant, :destroy?
    end

    def resolve(plant:, **_attributes)
      id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = plant.destroy
      errors = errors_from_active_record plant.errors
      {
        plant_id: result.destroyed? ? id : nil,
        errors: errors
      }
    end
  end
end
