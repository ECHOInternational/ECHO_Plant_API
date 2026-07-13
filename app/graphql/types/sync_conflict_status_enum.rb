# frozen_string_literal: true

module Types
  # Status values for SyncConflict records.
  class SyncConflictStatusEnum < Types::BaseEnum
    value 'open'
    value 'resolved'
    value 'dismissed'
  end
end
