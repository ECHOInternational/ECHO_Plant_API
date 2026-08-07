# frozen_string_literal: true

module Types
  # Metadata about a record's pending draft. Null when there is none.
  class RecordDraftInfoType < Types::BaseObject
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :author, String, null: true,
                           description: 'Display name of the principal who started this draft.'
    field :last_editor, String, null: true,
                                description: 'Display name of the principal who last edited it.'
    field :changed_fields, [String], null: false,
                                     description: 'Attribute names this draft changes.'
    field :is_stale, Boolean, null: false,
                              description: 'True when the live record changed a drafted field since this draft was ' \
                                           'started. Computing this queries the record\'s PaperTrail audit trail on ' \
                                           'every resolution -- avoid requesting it across large lists; batching it ' \
                                           'is a tracked follow-up.'

    def author
      object.author&.display_name
    end

    def last_editor
      object.last_editor&.display_name
    end

    def is_stale
      Drafts::ConflictDetector.new(object).conflicted_fields.any?
    end
  end
end
