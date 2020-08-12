# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field # :nodoc:
    argument_class Types::BaseArgument
  end
end
