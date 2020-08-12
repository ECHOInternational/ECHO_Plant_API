# frozen_string_literal: true

module Types
  class BaseInputObject < GraphQL::Schema::InputObject # :nodoc:
    argument_class Types::BaseArgument
  end
end
