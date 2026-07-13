# frozen_string_literal: true

# User class for storing information about the current user in memory.
#
# Built fresh on every request from the verified JWT payload. Never persisted.
# The durable identity lives in Principal (resolved by ApplicationController
# and attached here via principal=); organization memberships arrive in the
# token's user.organizations claim and are interpreted through
# OrganizationRole capabilities.
class User
  extend ActiveModel::Naming
  attr_reader :id, :email, :permissions, :organization_claims
  attr_accessor :principal, :personal_organization

  def initialize(options)
    @id = options['uid']
    @email = options['email']
    @permissions = options['trust_levels']
    @organization_claims = Array(options['organizations']).select do |claim|
      claim.is_a?(Hash) && claim['id'].present?
    end
  end

  # plant permissions
  # 0 = No Access
  # 1 = Read-Only Access
  # 2 = Read/Write Access
  # 3 ... 7 Future Use
  # 8 Can Create, Update, and Delete on behalf of other users and can
  #   Create and update public records... Cannot delete public records.
  # 9 Can delete public records

  def super_admin?
    @permissions['plant'] > 9
  end
  # The one global bypass in the target model (design.md D3). Alias kept so
  # new-model code reads in the new vocabulary while the trust ladder remains
  # the wire format.
  alias system_superuser? super_admin?

  def admin?
    # Can CRUD things with restricted ownership
    @permissions['plant'] > 8
  end

  def can_read?
    (@permissions['plant']).positive?
  end

  def can_write?
    @permissions['plant'] > 1
  end

  # --- Organization membership (new model) -------------------------------

  # Role held in the given organization, or nil. The personal organization's
  # implicit role tracks the legacy trust ladder so that shim orgs never widen
  # what a token could do before the redesign: writers manage their own
  # records (org_admin of their personal org), read-tier tokens only read.
  def role_in(organization_id)
    return nil if organization_id.nil?

    if personal_organization && organization_id == personal_organization.id
      return can_write? ? 'org_admin' : 'member'
    end

    claimed_role_for(organization_id)
  end

  def organization_capability?(organization_id, capability)
    role = role_in(organization_id)
    return false unless role

    OrganizationRole.capable?(role, capability)
  end

  # Organizations whose records this user may read: the personal org plus
  # every claimed org (every role includes :read). Used by policy scopes;
  # empty when the request never resolved a principal (schema-level specs,
  # anonymous) so legacy scope behavior is untouched.
  def readable_organization_ids
    @readable_organization_ids ||= begin
      ids = organization_claims.filter_map do |claim|
        claim['id'] if valid_role?(claim.dig('roles', 'plant'))
      end
      ids << personal_organization.id if personal_organization
      ids
    end
  end

  # True when some real-organization membership allows creating records.
  # The personal organization is deliberately excluded here: personal-org
  # creation is exactly the legacy can_write? path.
  def can_create_in_any_organization?
    organization_claims.any? do |claim|
      OrganizationRole.capable?(claim.dig('roles', 'plant'), :create)
    end
  end

  # Non-public read test for a single loaded record, mirroring the
  # authenticated branch of OwnedResourcePolicy::Scope (legacy email ownership
  # union organization membership). Used by loaded-association filters.
  def reads_owned_record?(record)
    record.owned_by == email ||
      readable_organization_ids.include?(record.owner_organization_id)
  end

  # Stable-creator check backing the contributor "update records they
  # created" capability. Email strings are never consulted here.
  def created_record?(record)
    principal &&
      record.respond_to?(:created_by_principal_id) &&
      record.created_by_principal_id.present? &&
      record.created_by_principal_id == principal.id
  end

  def to_model() end

  def to_s
    @id
  end

  def persisted?
    false
  end

  private

  def claimed_role_for(organization_id)
    claim = organization_claims.find { |c| c['id'] == organization_id }
    role = claim&.dig('roles', 'plant')
    valid_role?(role) ? role : nil
  end

  def valid_role?(role)
    OrganizationRole::ROLES.include?(role)
  end
end
