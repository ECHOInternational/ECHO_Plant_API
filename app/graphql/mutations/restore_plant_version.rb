# frozen_string_literal: true

module Mutations
  # Restores a plant to the state it had immediately after a chosen history
  # entry. Gated by the same update? policy that gates editing and reading the
  # history itself.
  class RestorePlantVersion < BaseMutation
    include Mutations::Concerns::ChangeEntryArgument

    argument :plant_id, ID, required: true, loads: Types::PlantType
    argument :version_id, ID, required: true,
                              description: 'The id of the ChangeEntry to restore, from recordHistory.'

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **_attributes)
      authorize plant, :update?
      true
    end

    def resolve(plant:, version_id:)
      decoded = decode_change_entry_id(version_id)
      return { plant: plant, errors: [change_entry_not_found_error] } if decoded.nil?

      result = ChangeHistory::Restorer.new(record: plant, version_id: decoded).call
      return { plant: plant, errors: result.errors } if result.errors.any?

      { plant: plant, errors: errors_from_active_record(plant.errors) }
    end
  end
end
