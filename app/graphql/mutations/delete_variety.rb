# frozen_string_literal: true

module Mutations
  # Deletes a Variety
  class DeleteVariety < BaseMutation
    argument :variety_id, ID,
             description: 'The variety to be deleted',
             required: true,
             loads: Types::VarietyType

    field :variety_id, ID, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(variety:, **_attributes)
      authorize variety, :destroy?
    end

    def resolve(variety:, **_attributes)
      id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = variety.destroy
      errors = errors_from_active_record variety.errors
      {
        variety_id: result ? id : nil,
        errors: errors
      }
    end
  end
end
