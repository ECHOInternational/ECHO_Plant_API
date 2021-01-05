# frozen_string_literal: true

module Mutations
  # Deletes an Location
  class DeleteLocation < BaseMutation
    argument :location_id, ID,
             description: 'The location to be deleted',
             required: true,
             loads: Types::LocationType

    field :location_id, ID, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(location:, **_attributes)
      authorize location, :destroy?
    end

    def resolve(location:, **_attributes)
      id = PlantApiSchema.id_from_object(location, Location, {})
      result = location.destroy
      errors = errors_from_active_record location.errors
      {
        location_id: result ? id : nil,
        errors: errors
      }
    end
  end
end
