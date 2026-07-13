# frozen_string_literal: true

# Represents an external system from which records can be imported. Credentials
# are never stored in the database; they live in environment variables or a
# secrets manager.
class DataSource < ApplicationRecord
  belongs_to :organization

  validates :name,              presence: true
  validates :source_system_key, presence: true
  validates :organization,      presence: true
end
