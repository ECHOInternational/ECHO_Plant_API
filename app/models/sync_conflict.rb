# frozen_string_literal: true

# Records a three-way conflict detected during a sync run. The three payloads
# capture what the source had at the last sync (base), what the local record
# currently is (local), and what the source now says (incoming). Only attributes
# in the source-managed set are compared; authorization/workflow state is never
# feed-writable.
class SyncConflict < ApplicationRecord
  CONFLICT_TYPES = %w[content source_deletion].freeze
  STATUSES       = %w[open resolved dismissed].freeze

  belongs_to :syncable, polymorphic: true
  belongs_to :data_source
  belongs_to :resolved_by_principal, class_name: 'Principal', optional: true

  validates :conflict_type, presence: true, inclusion: { in: CONFLICT_TYPES }
  validates :status,        presence: true, inclusion: { in: STATUSES }
  validates :data_source,   presence: true
  validates :syncable,      presence: true

  scope :open_conflicts, -> { where(status: 'open') }
end
