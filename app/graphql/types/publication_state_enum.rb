# frozen_string_literal: true

module Types
  # Publication state for independently-owned records (design.md section 5).
  class PublicationStateEnum < Types::BaseEnum
    description 'Whether a record is a working draft or published.'

    value 'DRAFT',     value: 'draft',      description: 'Record is a working draft not yet published.'
    value 'PUBLISHED', value: 'published',  description: 'Record is published.'
  end
end
