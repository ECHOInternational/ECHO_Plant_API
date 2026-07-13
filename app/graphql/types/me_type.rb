# frozen_string_literal: true

module Types
  # The currently authenticated user, resolved from the request context.
  # Null when the request is anonymous (the me query field itself is null: true).
  class MeType < Types::BaseObject
    description 'The currently authenticated user.'

    field :email, String, null: false,
                          description: 'The email address from the JWT claim.'
    field :display_name, String, null: true,
                                 description: 'Human-readable display name from the resolved principal.'
    field :principal_id, ID, null: true,
                             description: 'Relay global ID of the resolved Principal record, if available.'
    field :organizations, [Types::MeOrganizationType], null: false,
                                                       description: 'Organizations the user belongs to, including their personal organization.'

    def email
      @object.email
    end

    def display_name
      @object.principal&.display_name
    end

    def principal_id
      principal = @object.principal
      return nil unless principal

      PlantApiSchema.id_from_object(principal, Types::PrincipalType, context)
    end

    def organizations
      user = @object
      result = []

      # Personal organization entry (always present when a principal is resolved)
      if user.personal_organization
        role = user.role_in(user.personal_organization.id)
        result << { organization: user.personal_organization, role: role } if role
      end

      # Claimed real-org entries from the JWT organizations claim.
      # In the test convention (and the transition-era policy system) claim['id']
      # is the local organization UUID (owner_organization_id FK). In production
      # the IdP mirror upsert keeps claim['id'] aligned with the local id via
      # the external_idp_id column; fall back to external_idp_id lookup when
      # the local-id lookup finds nothing.
      user.organization_claims.each do |claim|
        org = Organization.find_by(id: claim['id']) ||
              Organization.find_by(external_idp_id: claim['id'])
        next unless org

        role = user.role_in(org.id)
        next unless role

        result << { organization: org, role: role }
      end

      result
    end
  end
end
