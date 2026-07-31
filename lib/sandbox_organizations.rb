# frozen_string_literal: true

# Parses the SANDBOX_ORGS development env var into JWT-shaped organization
# claims, so a local sandbox run can exercise organization membership without
# an IdP issuing tokens.
#
# Without it the sandbox user belongs only to its personal organization, which
# means every organization-aware surface (the admin SPA workspace switcher, org
# capability checks, the visibility facade) is untestable locally.
#
# Format: comma separated entries, each "Name" or "Name:role".
#
#   SANDBOX_ORGS='ECHO Asia Impact Center:org_admin,ECHO North America:editor'
#
# Roles are the OrganizationRole names; entries naming an unknown role are
# skipped with a warning rather than silently granting nothing, since a typo
# would otherwise look like a capability bug.
#
# Ids are UUIDv5 values derived from the name, so a given name always maps to
# the same organization across restarts. That matters because a mirrored real
# organization adopts the claim id as its LOCAL primary key, so the id must be
# a stable, well-formed UUID.
module SandboxOrganizations
  # Fixed namespace for deriving org ids. Arbitrary but must never change, or
  # existing sandbox databases would grow a second row per organization name.
  NAMESPACE = 'f1b9c0e6-5c2a-4c8e-9d3a-7a2b6e4d1c05'
  DEFAULT_ROLE = 'org_admin'

  # Claims for the sandbox user, shaped exactly like the JWT organizations
  # claim. Empty when SANDBOX_ORGS is unset.
  def self.claims
    parse(ENV.fetch('SANDBOX_ORGS', nil))
  end

  def self.parse(raw)
    value = unquote(raw.to_s.strip)
    return [] if value.blank?

    value.split(',').filter_map { |entry| claim_for(entry) }
  end

  # docker compose reads .env through env_file, which does NOT strip quotes the
  # way dotenv does, so SANDBOX_ORGS='a,b' arrives with the quotes attached.
  # Tolerate a wrapping pair rather than creating an organization whose name
  # starts with a stray quote.
  def self.unquote(value)
    value.sub(/\A(['"])(.*)\1\z/m, '\2')
  end
  private_class_method :unquote

  def self.id_for(name)
    Digest::UUID.uuid_v5(NAMESPACE, name)
  end

  def self.claim_for(entry)
    name, role = entry.split(':', 2).map { |part| part.to_s.strip }
    return if name.blank?

    role = DEFAULT_ROLE if role.blank?
    unless OrganizationRole::ROLES.include?(role)
      Rails.logger.warn("SANDBOX_ORGS: skipping #{name.inspect}, unknown role #{role.inspect}")
      return
    end

    { 'id' => id_for(name), 'name' => name, 'roles' => { 'plant' => role } }
  end
  private_class_method :claim_for
end
