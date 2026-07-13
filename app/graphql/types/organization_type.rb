# frozen_string_literal: true

module Types
  # Exposes the local Organization mirror on the GraphQL surface.
  # Real organizations are upserted from JWT claims; personal organizations
  # are single-principal shims created on demand (design.md section 2).
  class OrganizationType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A local mirror of an IdP organization, or a personal organization shim.'

    field :name, String, null: false,
                         description: 'Human-readable organization name.'
    field :kind, String, null: false,
                         description: 'Either real (IdP-backed) or personal (single-principal shim).'
  end
end
