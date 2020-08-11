module Mutations
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
  end
end
