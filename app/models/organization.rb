# frozen_string_literal: true

# Local mirror and shim for organizations. Real organizations are upserted from
# JWT claims; personal organizations are created on demand for each principal.
class Organization < ApplicationRecord
  belongs_to :principal, optional: true

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: %w[real personal] }

  with_options if: -> { kind == "real" } do
    validates :external_idp_id, presence: true
    validates :principal_id,    absence: true
  end

  with_options if: -> { kind == "personal" } do
    validates :principal_id,    presence: true
    validates :external_idp_id, absence: true
  end

  # Returns the personal organization for the given principal, creating it if
  # needed.
  def self.personal_for!(principal)
    find_or_create_by!(principal_id: principal.id) do |org|
      org.name = principal.display_name.presence || principal.email
      org.kind = "personal"
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(principal_id: principal.id)
  end

  # Upserts a real (IdP-backed) organization by its IdP UUID, refreshing name
  # if it has changed.
  #
  # INVARIANT: a mirrored real organization adopts the IdP UUID as its LOCAL
  # primary key (id == external_idp_id). JWT organization claims carry the IdP
  # UUID, and every capability check compares claim ids against records'
  # owner_organization_id; a separately generated local id would make those
  # comparisons never match in production. Personal orgs keep their own
  # generated UUIDs (v4 collision risk with IdP-issued UUIDs is negligible).
  def self.mirror_real!(external_id:, name:)
    org = find_or_create_by!(external_idp_id: external_id) do |o|
      o.id = external_id
      o.name = name
      o.kind = "real"
    end
    org.update!(name: name) if org.name != name
    org
  rescue ActiveRecord::RecordNotUnique
    org = find_by!(external_idp_id: external_id)
    org.update!(name: name) if org.name != name
    org
  end
end
