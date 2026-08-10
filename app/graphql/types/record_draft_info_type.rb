# frozen_string_literal: true

module Types
  # Metadata about a record's pending draft. Null when there is none.
  class RecordDraftInfoType < Types::BaseObject
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :author, String, null: true,
                           description: 'Display name of the principal who started this draft, falling back to ' \
                                        'their email when no display name is on file.'
    field :last_editor, String, null: true,
                                description: 'Display name of the principal who last edited it, falling back to ' \
                                             'their email when no display name is on file.'
    field :changed_fields, [String], null: false,
                                     description: 'Attribute names this draft changes.'
    field :is_stale, Boolean, null: false,
                              description: 'True when the live record changed a drafted field since this draft was ' \
                                           'started. Computing this queries the record\'s PaperTrail audit trail on ' \
                                           'every resolution -- avoid requesting it across large lists; batching it ' \
                                           'is a tracked follow-up.'

    # display_name is not always populated: resolve_actor (application_controller.rb)
    # never passes it when it upserts a Principal from a JWT claim, so it is nil for
    # most real users today and this field would otherwise render "Unknown" client
    # side. Fall back to email, which this type's callers (editors, gated by
    # DraftFields#draft requiring update?) already see elsewhere on the record via
    # ownedBy/createdBy, so this is no new exposure.
    def author
      object.author&.display_name.presence || object.author&.email
    end

    def last_editor
      object.last_editor&.display_name.presence || object.last_editor&.email
    end

    def is_stale
      Drafts::ConflictDetector.new(object).conflicted_fields.any?
    end
  end
end
