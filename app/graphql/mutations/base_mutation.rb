# frozen_string_literal: true

module Mutations
  # All mutations inherit from this set of defaults
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Pundit
    def pundit_user
      context[:current_user]
    end
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject
    null false

    def errors_from_active_record(errors, field_mappings = {})
      mutation_errors = []
      return mutation_errors if errors.empty?

      errors.each do |attribute, error|
        mutation_errors << {
          field: field_mappings[attribute] || attribute,
          message: "#{attribute} #{error}",
          code: 400
        }
      end
      mutation_errors
    end
  end
end
