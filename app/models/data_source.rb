# frozen_string_literal: true

# Represents an external system from which records can be imported. Credentials
# are never stored in the database; they live in environment variables or a
# secrets manager.
class DataSource < ApplicationRecord
  belongs_to :organization

  validates :name,              presence: true
  validates :source_system_key, presence: true
  validates :organization,      presence: true

  # Returns (or creates) the service principal used for PaperTrail attribution
  # when this data source runs a sync. The principal is identified by
  # identity_issuer='sync' and the source-system-scoped email address.
  # Because external_uid is nil, the partial unique index does not apply;
  # identity is stabilized by (identity_issuer, email).
  def service_principal!
    email = "sync+#{source_system_key}@plant-api.echocommunity.org"
    Principal.find_or_create_by!(identity_issuer: 'sync', email: email) do |p|
      p.kind         = 'service'
      p.external_uid = nil
      p.display_name = "Sync service for #{name}"
    end
  rescue ActiveRecord::RecordNotUnique
    Principal.find_by!(identity_issuer: 'sync', email: email)
  end
end
