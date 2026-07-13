# frozen_string_literal: true

module Types
  # Exposes a DataSource record on the GraphQL surface.
  class DataSourceType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    field :name,              String, null: false
    field :source_system_key, String, null: false
    field :organization,      Types::OrganizationType, null: false
  end
end
