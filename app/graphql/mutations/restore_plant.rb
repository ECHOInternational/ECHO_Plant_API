# frozen_string_literal: true

module Mutations
  # Restores a soft-deleted Plant. Clearing deleted_at lets the dual-write
  # recompute visibility from the preserved publication_state/access_level,
  # which is better than the legacy restore-to-private outcome.
  class RestorePlant < BaseMutation
    argument :plant_id, ID,
             description: 'The plant to be restored.',
             required: true,
             loads: Types::PlantType

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **_attributes)
      authorize plant, :restore?
    end

    def resolve(plant:, **_attributes)
      unless plant.visibility.to_s == 'deleted'
        return {
          plant: plant,
          errors: [{
            field: 'plantId',
            message: 'record is not deleted',
            code: 400
          }]
        }
      end

      plant.update(deleted_at: nil, deleted_by_principal_id: nil)
      {
        plant: plant,
        errors: errors_from_active_record(plant.errors)
      }
    end
  end
end
