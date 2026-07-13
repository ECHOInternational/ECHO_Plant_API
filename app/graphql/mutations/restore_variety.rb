# frozen_string_literal: true

module Mutations
  # Restores a soft-deleted Variety. Clearing deleted_at lets the dual-write
  # recompute visibility from the preserved publication_state/access_level,
  # which is better than the legacy restore-to-private outcome.
  class RestoreVariety < BaseMutation
    argument :variety_id, ID,
             description: 'The variety to be restored.',
             required: true,
             loads: Types::VarietyType

    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(variety:, **_attributes)
      authorize variety, :restore?
    end

    def resolve(variety:, **_attributes)
      unless variety.visibility.to_s == 'deleted'
        return {
          variety: variety,
          errors: [{
            field: 'varietyId',
            message: 'record is not deleted',
            code: 400
          }]
        }
      end

      variety.update(deleted_at: nil, deleted_by_principal_id: nil)
      {
        variety: variety,
        errors: errors_from_active_record(variety.errors)
      }
    end
  end
end
