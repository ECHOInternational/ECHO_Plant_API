# frozen_string_literal: true

# Central role-to-capability mapping for organization memberships (design.md
# section 3). Policies ask about capabilities, never about role names or
# numeric comparisons, so capability semantics live in exactly one place.
#
# Roles are strings as delivered by the IdP JWT organizations claim
# (roles: { "plant" => "editor" }). Unknown role strings grant nothing,
# which makes future IdP-side role additions forward-compatible.
module OrganizationRole
  ROLES = %w[member contributor editor steward org_admin].freeze

  CAPABILITIES = {
    'member' => %i[read].freeze,
    'contributor' => %i[read create update_own].freeze,
    'editor' => %i[read create update_own update_any
                   resolve_conflicts].freeze,
    'steward' => %i[read create update_own update_any resolve_conflicts
                    soft_delete restore accept_source_deletion].freeze,
    'org_admin' => %i[read create update_own update_any resolve_conflicts
                      soft_delete restore accept_source_deletion
                      manage_org].freeze
  }.freeze

  def self.capable?(role, capability)
    CAPABILITIES.fetch(role, []).include?(capability)
  end
end
