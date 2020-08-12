# frozen_string_literal: true

module Types
  class BaseObject < GraphQL::Schema::Object # :nodoc:
    field_class Types::BaseField
  end
end
