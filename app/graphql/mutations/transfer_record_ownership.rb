# frozen_string_literal: true

module Mutations
  # Transfers ownership of an independently-owned record to a different
  # organization. The caller must have soft_delete capability on the record
  # (steward or org_admin of the current owner org, or legacy admin). The
  # target organization must exist in the local mirror. Source organization
  # is preserved (records origin from the old owner).
  class TransferRecordOwnership < BaseMutation
    argument :record_id, ID,
             required: true,
             description: 'Relay global ID of the record to transfer (Plant, Variety, Specimen, Location, or Category).'
    argument :to_organization_id, ID,
             required: true,
             description: 'Relay global ID of the organization that will become the new owner.'

    field :record, Types::OwnedRecordUnion,
          null: true,
          description: 'The transferred record with updated ownerOrganization.'
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      # Ownership transfer is a system-superuser-only capability (design.md
      # section 8). Raise immediately so the schema rescue produces a 403.
      unless context[:current_user]&.system_superuser?
        raise Pundit::NotAuthorizedError.new(
          query: :transfer_record_ownership,
          record: :transfer,
          policy: nil
        )
      end

      true
    end

    def resolve(record_id:, to_organization_id:)
      record, load_err = load_record(record_id)
      return { record: nil, errors: [load_err] } if load_err

      org, org_err = load_organization(to_organization_id)
      return { record: nil, errors: [org_err] } if org_err

      record.update(owner_organization_id: org.id)
      {
        record: record,
        errors: errors_from_active_record(record.errors)
      }
    end

    OWNED_RECORD_CLASSES = [Plant, Variety, Specimen, Location, Category].freeze

    private

    def load_record(record_id)
      obj = PlantApiSchema.object_from_id(record_id, {})
      unless OWNED_RECORD_CLASSES.include?(obj.class)
        return [nil, {
          field: 'recordId',
          message: "Record #{record_id} is not an independently-owned record type.",
          code: 400
        }]
      end

      [obj, nil]
    rescue ActiveRecord::RecordNotFound
      [nil, {
        field: 'recordId',
        message: "Record #{record_id} not found.",
        code: 404
      }]
    end

    def load_organization(to_organization_id)
      _type_name, raw_id = GraphQL::Schema::UniqueWithinType.decode(to_organization_id)
      org = Organization.find(raw_id)
      [org, nil]
    rescue ActiveRecord::RecordNotFound, ArgumentError
      [nil, {
        field: 'toOrganizationId',
        message: "Organization #{to_organization_id} not found.",
        code: 404
      }]
    end
  end
end
