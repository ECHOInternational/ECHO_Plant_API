# frozen_string_literal: true

module Mutations
  # Restores a soft-deleted Location. Clearing deleted_at lets the dual-write
  # recompute visibility from the preserved publication_state/access_level,
  # which is better than the legacy restore-to-private outcome.
  class RestoreLocation < BaseMutation
    argument :location_id, ID,
             description: 'The location to be restored.',
             required: true,
             loads: Types::LocationType

    field :location, Types::LocationType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(location:, **_attributes)
      authorize location, :restore?
    end

    def resolve(location:, **_attributes)
      unless location.visibility.to_s == 'deleted'
        return {
          location: location,
          errors: [{
            field: 'locationId',
            message: 'record is not deleted',
            code: 400
          }]
        }
      end

      location.update(deleted_at: nil, deleted_by_principal_id: nil)
      {
        location: location,
        errors: errors_from_active_record(location.errors)
      }
    end
  end
end
