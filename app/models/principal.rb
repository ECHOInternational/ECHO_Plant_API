# frozen_string_literal: true

# Represents a durable identity that can be resolved from a JWT claim or
# synthesized for legacy/service actors. External identity is identified by
# (identity_issuer, external_uid); legacy principals have external_uid nil.
class Principal < ApplicationRecord
  has_one :personal_organization, class_name: 'Organization', foreign_key: :principal_id

  validates :identity_issuer, presence: true
  validates :email,           presence: true
  validates :kind,            presence: true, inclusion: { in: %w[human service] }

  LEGACY_ISSUER = 'legacy-email'
  SHARED_ISSUER = 'legacy-shared'

  # Resolves or creates a principal by (issuer, uid), refreshing mutable
  # profile fields only when they change or last_authenticated_at is stale.
  # Handles the create-race by rescuing RecordNotUnique and retrying the find.
  def self.resolve!(issuer:, external_uid:, email: nil, display_name: nil)
    record = find_by(identity_issuer: issuer, external_uid: external_uid)
    if record.nil?
      record = create!(
        identity_issuer: issuer,
        external_uid: external_uid,
        email: email || 'unknown@unknown',
        display_name: display_name,
        kind: 'human',
        last_authenticated_at: Time.current
      )
    end
    refresh_if_stale!(record, email: email, display_name: display_name)
    record
  rescue ActiveRecord::RecordNotUnique
    record = find_by!(identity_issuer: issuer, external_uid: external_uid)
    refresh_if_stale!(record, email: email, display_name: display_name)
    record
  end

  # Finds or creates a legacy principal identified only by email address.
  # Used by the backfill for owners whose JWT uid is not yet known.
  def self.legacy_for_email(email)
    find_or_create_by!(identity_issuer: LEGACY_ISSUER, email: email) do |p|
      p.kind         = 'human'
      p.external_uid = nil
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(identity_issuer: LEGACY_ISSUER, email: email)
  end

  private_class_method def self.refresh_if_stale!(record, email:, display_name:)
    changed_fields = stale_profile_fields(record, email, display_name)
    changed_fields[:last_authenticated_at] = Time.current if stale_auth?(record)

    record.update!(changed_fields) if changed_fields.any?
  end

  def self.stale_profile_fields(record, email, display_name)
    fields = {}
    fields[:email]        = email        if email.present? && record.email != email
    fields[:display_name] = display_name if display_name.present? && record.display_name != display_name
    fields
  end
  private_class_method :stale_profile_fields

  def self.stale_auth?(record)
    record.last_authenticated_at.nil? || record.last_authenticated_at < 1.hour.ago
  end
  private_class_method :stale_auth?
end
