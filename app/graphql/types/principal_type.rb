# frozen_string_literal: true

module Types
  # Exposes a resolved principal (durable identity) on the GraphQL surface.
  # Principals are resolved from JWT claims or synthesized for legacy actors.
  # Email is exposed for parity with the existing ownedBy/createdBy fields.
  class PrincipalType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A durable identity resolved from a JWT claim or synthesized for a legacy actor.'

    field :display_name, String, null: true,
                                 description: 'Human-readable name from the identity provider.'
    field :email, String, null: true,
                          description: 'Mutable profile email. Mirrors the legacy createdBy/ownedBy strings.'
  end
end
