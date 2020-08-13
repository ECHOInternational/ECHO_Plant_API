# frozen_string_literal: true

module Types
  # Defines a mutation error type for other types to inherit from
  class MutationError < Types::BaseObject
    field :field, String,
          description: 'The field that generated the error',
          null: false
    field :value, String,
          description: 'The value that generated the error',
          null: true
    field :message, String,
          description: 'A human readable error message',
          null: false
    field :code, Integer,
          description: 'A numeric code that indicates the status of the error. Uses standard HTTP status codes.',
          null: false
  end
end
