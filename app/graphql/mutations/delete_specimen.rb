# frozen_string_literal: true

module Mutations
  # Deletes an Specimen
  class DeleteSpecimen < BaseMutation
    argument :specimen_id, ID,
             description: 'The specimen to be deleted',
             required: true,
             loads: Types::SpecimenType

    field :specimen_id, ID, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(specimen:, **_attributes)
      authorize specimen, :destroy?
    end

    def resolve(specimen:, **_attributes)
      id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = specimen.destroy
      errors = errors_from_active_record specimen.errors
      {
        specimen_id: result ? id : nil,
        errors: errors
      }
    end
  end
end
