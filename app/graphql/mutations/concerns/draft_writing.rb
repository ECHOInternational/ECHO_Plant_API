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
                      description: 'Stage these changes on a draft instead of writing the live record. ' \
                                   'Only draftable columns (DraftableAttributes) are staged: workflow ' \
                                   'arguments such as visibility, publicationState and accessLevel, and any ' \
                                   'other non-column argument sent alongside saveAsDraft, are silently ' \
                                   'ignored rather than staged -- they take effect only on a live (non-draft) write.'
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
        scalars = stage_family_id(scalars, attributes, permitted)
        staged_translations = attrs.slice(*record.class.mobility_attributes.map(&:to_s))
        return scalars if staged_translations.empty?

        scalars.merge('translations' => merged_translations_blob(record, staged_translations, language))
      end

      # plants.family_id is an ordinary draftable column (design doc), but
      # UpdatePlant's familyId argument uses `loads:`, so graphql-ruby hands
      # resolve a loaded Family record (or explicit nil) under :family, never
      # a literal family_id string -- the generic slice above can never see
      # it. Stage it explicitly, mirroring the `attributes.key?(:family)`
      # idiom FamilyAssignment#apply_family already uses, so `familyId: null`
      # (key present, value nil) stages a clear rather than being skipped as
      # absent. Guarded on the whitelist so this is a no-op for models (and
      # UpdateFamily's own `family` kwarg, which names the record being
      # edited, not an assignment) that don't draft family_id at all.
      def stage_family_id(scalars, attributes, permitted)
        return scalars unless permitted.include?('family_id') && attributes.key?(:family)

        scalars.merge('family_id' => attributes[:family]&.id)
      end

      # Merges the newly staged fields into whatever translations blob is
      # already on the draft, so saving one locale never clobbers another.
      #
      # Deliberately NOT seeded from record.translations on first save: the
      # draft blob holds only the locales/fields the editor actually staged,
      # not a full snapshot of the live translations. Overlay and Publisher
      # both deep-merge the draft onto the live record when reading/publishing,
      # so a "changed keys only" blob renders and publishes identically to a
      # full snapshot while staying small and free of stale-copy drift.
      def merged_translations_blob(record, staged_translations, language)
        locale = (language || Mobility.locale).to_s
        blob = (record.record_draft&.data&.dig('translations') || {}).deep_dup
        blob[locale] = (blob[locale] || {}).merge(staged_translations)
        blob
      end
    end
  end
end
