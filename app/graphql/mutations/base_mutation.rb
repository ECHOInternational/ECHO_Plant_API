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
