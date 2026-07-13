# frozen_string_literal: true

module Mutations
  # All mutations inherit from this set of defaults
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Pundit::Authorization
    def pundit_user
      context[:current_user]
    end
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject
    null false

    # Server-assigned ownership/provenance fields for newly created
    # independently-owned records (design.md sections 1 and 4). Never
    # client-suppliable. Empty when the request has no resolved principal
    # (schema-level specs, pre-rollout tokens), leaving legacy behavior
    # untouched. A native record's source organization equals its owner.
    def ownership_stamp
      user = context[:current_user]
      return {} unless user&.principal

      org_id = user.personal_organization&.id
      {
        created_by_principal_id: user.principal.id,
        owner_organization_id: org_id,
        source_organization_id: org_id
      }
    end

    # Acting-organization stamp: like ownership_stamp but uses the specified
    # organization (decoded from a Relay global ID) as the owner and source
    # instead of the personal organization. The caller is responsible for
    # verifying that organization_id is present before calling this method.
    # Returns a payload error hash (not raises) if the organization is not found,
    # so callers must check the return value:
    #   stamp, err = acting_organization_stamp(org_id)
    #   return { resource: nil, errors: [err] } if err
    def acting_organization_stamp(organization_id)
      user = context[:current_user]
      unless user&.principal
        return [{
          created_by_principal_id: nil,
          owner_organization_id: nil,
          source_organization_id: nil
        }, nil]
      end

      begin
        _type_name, raw_id = GraphQL::Schema::UniqueWithinType.decode(organization_id)
        org = Organization.find(raw_id)
      rescue ActiveRecord::RecordNotFound, ArgumentError
        err = {
          field: 'organizationId',
          message: "Organization #{organization_id} not found.",
          code: 404
        }
        return [nil, err]
      end

      unless user.organization_capability?(org.id, :create) ||
             (user.personal_organization && org.id == user.personal_organization.id)
        raise Pundit::NotAuthorizedError.new(
          query: :create,
          record: org,
          policy: nil
        )
      end

      stamp = {
        created_by_principal_id: user.principal.id,
        owner_organization_id: org.id,
        source_organization_id: org.id
      }
      [stamp, nil]
    end

    # Shared visibility-transition gate for update mutations that accept a
    # legacy visibility argument (design.md section 5 and Phase C item 5).
    # Call from authorized? after the base :update? check.
    #
    # Rules:
    #   transitioning TO deleted  -> require soft_delete? in addition to update?
    #   transitioning FROM deleted (restoring) -> require restore?
    #   otherwise -> no additional check
    def authorize_visibility_transition(record, visibility_arg)
      return unless visibility_arg

      going_deleted = visibility_arg.to_s.casecmp('deleted').zero?
      currently_deleted = record.visibility.to_s == 'deleted'

      if going_deleted && !currently_deleted
        authorize record, :soft_delete?
      elsif !going_deleted && currently_deleted
        authorize record, :restore?
      end
    end

    def errors_from_active_record(errors, field_mappings = {})
      mutation_errors = []
      return mutation_errors if errors.empty?

      errors.each do |error|
        attribute = error.attribute
        mutation_errors << {
          field: field_mappings[attribute] || attribute,
          message: "#{attribute} #{error.message}",
          code: 400
        }
      end
      mutation_errors
    end
  end
end
