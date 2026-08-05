# frozen_string_literal: true

module Mutations
  # Restores a variety to the state it had immediately after a chosen history
  # entry. Gated by the same update? policy that gates editing and reading the
  # history itself.
  class RestoreVarietyVersion < BaseMutation
    include Mutations::Concerns::ChangeEntryArgument

    argument :variety_id, ID, required: true, loads: Types::VarietyType
    argument :version_id, ID, required: true,
                              description: 'The id of the ChangeEntry to restore, from recordHistory.'

    field :variety, Types::VarietyType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(variety:, **_attributes)
      authorize variety, :update?
      true
    end

    def resolve(variety:, version_id:)
      decoded = decode_change_entry_id(version_id)
      return { variety: variety, errors: [change_entry_not_found_error] } if decoded.nil?

      result = ChangeHistory::Restorer.new(record: variety, version_id: decoded).call
      return { variety: variety, errors: result.errors } if result.errors.any?

      { variety: variety, errors: errors_from_active_record(variety.errors) }
    end
  end
end
