# frozen_string_literal: true

module Types
  # Access level for independently-owned records (design.md section 5).
  class AccessLevelEnum < Types::BaseEnum
    description 'Whether a record is visible to the owning organization only or to the public.'

    value 'ORGANIZATION', value: 'organization',
                          description: 'Visible only to members of the owning organization.'
    value 'PUBLIC',       value: 'public',
                          description: 'Publicly visible to any reader.'
  end
end
