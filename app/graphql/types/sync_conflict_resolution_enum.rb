# frozen_string_literal: true

module Types
  # Resolution choices for the resolveSyncConflict mutation.
  class SyncConflictResolutionEnum < Types::BaseEnum
    value 'KEEP_LOCAL',
          'Keep local values as canonical; adopt them as the new sync base'
    value 'ACCEPT_INCOMING',
          'Accept the incoming source values, or accept the upstream deletion'
  end
end
