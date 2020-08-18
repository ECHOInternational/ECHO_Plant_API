# frozen_string_literal: true

module Types
  # Defines fields for a common name
  class CommonNameType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A language-specific name for a plant which can also reference a location where that name is common.'

    field :uuid, ID,
          description: 'The internal database ID for a common name',
          null: false,
          method: :id
    field :name, String,
          description: 'The common name',
          null: false
    field :language, String,
          description: 'The language of the name',
          null: false
    field :location, String,
          description: 'The location where the name is common',
          null: true
    field :primary, Boolean,
          description: 'Indicates if the common name is a primary common name for the language indicated',
          null: false
  end
end
