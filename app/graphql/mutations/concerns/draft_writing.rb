# frozen_string_literal: true

module Mutations
  module Concerns
    # Adds the saveAsDraft argument and the write path behind it.
    #
    # The API deliberately keeps the ability to write live directly:
    # SourceSynchronizer, the importers and the mobile app all need it. "Live is
    # only touched by Publish" is an editing-UI policy, not an API restriction.
    module DraftWriting
      def self.included(base)
        base.argument :save_as_draft, GraphQL::Types::Boolean,
                      required: false,
                      default_value: false,
                      description: 'Stage these changes on a draft instead of writing the live record.'
      end

      # Merges the supplied attributes into the record's draft, creating it on
      # first use. Returns the draft.
      #
      # base_updated_at is set ONLY at creation. Advancing it on every save
      # would silently swallow a conflict that arrived mid-draft.
      def write_draft(record, attributes, language: nil)
        permitted = DraftableAttributes.for(record.class)
        incoming = stageable_data(record, attributes, permitted, language)

        draft = record.record_draft
        principal_id = context[:current_user]&.principal&.id

        if draft
          draft.update!(data: draft.data.merge(incoming), last_editor_principal_id: principal_id)
        else
          draft = RecordDraft.create!(
            draftable: record,
            data: incoming,
            base_updated_at: record.updated_at,
            author_principal_id: principal_id,
            last_editor_principal_id: principal_id
          )
        end
        draft
      end

      private

      # Translatable fields have to be staged as a container blob keyed by
      # locale, not as bare scalars, or a staged Swahili description would
      # overwrite the English on publish. Building the blob against the record's
      # CURRENT translations keeps every other locale intact.
      def stageable_data(record, attributes, permitted, language)
        attrs = attributes.stringify_keys
        scalars = attrs.slice(*permitted)
        staged_translations = attrs.slice(*record.class.mobility_attributes.map(&:to_s))
        return scalars if staged_translations.empty?

        scalars.merge('translations' => merged_translations_blob(record, staged_translations, language))
      end

      # Merges the newly staged fields into whatever translations blob is
      # already on the draft (or, on first save, the live record), so saving
      # one locale never clobbers another.
      def merged_translations_blob(record, staged_translations, language)
        locale = (language || Mobility.locale).to_s
        blob = (record.record_draft&.data&.dig('translations') || record.translations || {}).deep_dup
        blob[locale] = (blob[locale] || {}).merge(staged_translations)
        blob
      end
    end
  end
end
