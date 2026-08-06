# frozen_string_literal: true

module ChangeHistory
  # Restores a plant or variety to the state it had immediately AFTER a chosen
  # entry, by reifying the version that follows it in that record's chain (a
  # PaperTrail version stores the state BEFORE its own change).
  #
  # Only editable content attributes are applied: the set the Update mutations
  # accept, plus the whole Mobility container column. Ownership, visibility, the
  # publication trio, sync bookkeeping and timestamps are never written, so the
  # OrganizedResource dual-write invariant cannot be violated and the sync
  # machinery sees a restore as an ordinary edit. PaperTrail stays audit-only.
  #
  # Child rows (common names, relation links, images) are out of scope for v1.
  class Restorer
    Result = Struct.new(:record, :errors, keyword_init: true)

    ERROR_FIELD = 'versionId'

    PLANT_ATTRIBUTES = (
      %w[scientific_name family_names early_growth_phase life_cycle translations] +
      Mutations::Concerns::PlantEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
      Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
    ).freeze

    VARIETY_ATTRIBUTES = (
      %w[translations] +
      Mutations::Concerns::VarietyEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
      Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
    ).freeze

    RESTORABLE_ATTRIBUTES = {
      'Plant' => PLANT_ATTRIBUTES,
      'Variety' => VARIETY_ATTRIBUTES
    }.freeze

    def initialize(record:, version_id:)
      @record = record
      @version_id = version_id
      @item_type = record.class.base_class.name
    end

    def call
      # Reload before anything reads or writes @record: a caller may hand us
      # an instance with unsaved changes (e.g. from a prior form build), and
      # both the trash guard below and Record#update must see -- and only
      # ever persist -- the actual database state, never attributes the
      # caller happened to have pending.
      @record.reload

      guard = guard_error
      return Result.new(record: @record, errors: [guard]) if guard

      apply(restorable_attributes)
      Result.new(record: @record, errors: [])
    end

    private

    def guard_error
      return error(404, 'That change entry does not belong to this record.') if version.nil?

      return error(400, 'Restore this record from the trash before restoring an earlier change.') if @record.respond_to?(:visibility_deleted?) && @record.visibility_deleted?

      return error(400, 'That change is already the current state of this record.') if successor.nil?
      return error(400, 'That change cannot be restored: its stored state is unreadable.') if reified.nil?

      nil
    end

    def version
      return @version if defined?(@version)

      @version = PaperTrail::Version.find_by(id: @version_id, item_type: @item_type, item_id: @record.id)
    end

    def successor
      return @successor if defined?(@successor)

      @successor = PaperTrail::Version
                   .where(item_type: @item_type, item_id: @record.id)
                   .where('versions.id > ?', version.id)
                   .order(:id)
                   .first
    end

    def reified
      return @reified if defined?(@reified)

      @reified = begin
        successor.reify
      rescue StandardError => e
        Rails.logger.warn("ChangeHistory::Restorer could not reify version #{successor.id}: #{e.class}")
        nil
      end
    end

    def restorable_attributes
      allowed = RESTORABLE_ATTRIBUTES.fetch(@item_type, [])
      attrs = reified.attributes.slice(*allowed)
      # `translations` is `jsonb NOT NULL DEFAULT '{}'`. Mobility's container
      # backend declares it with `store :translations, coder:
      # Mobility::Backends::ActiveRecord::Container::Coder` (plain
      # ActiveRecord::Store); Store#store wraps that Coder in an
      # ActiveRecord::Store::IndifferentCoder and declares the column via
      # `serialize`, so the column's ActiveRecord type ends up
      # ActiveRecord::Type::Serialized using that composite as `coder`.
      # Type::Serialized#serialize special-cases any assigned value that
      # equals `coder.load(nil)` -- which evaluates to a bare `{}`, since the
      # inner Coder's own #dump strips every blank leaf down to nothing -- and
      # returns nil for it instead of dumping it, so the write hits the column
      # as SQL NULL and the NOT NULL constraint rejects it. Empirically
      # verified against this schema: both `record.update!(translations: {})`
      # and `record.update!(translations: nil)` raise
      # ActiveRecord::NotNullViolation. A captured version whose translations
      # were blank at that point in history reifies to exactly that bare `{}`,
      # so there is no assignable value -- nil, {}, or anything else that
      # honestly represents "empty" -- that can persist it back through a
      # normal write. Dropping the key is the only fix at this layer: Rails'
      # partial write then never touches the column, leaving the record's
      # current value alone.
      #
      # That has a real semantic consequence, accepted here rather than fixed:
      # if the *target* version's translations were genuinely empty, this
      # restore keeps the record's CURRENT translated content in place instead
      # of clearing it, and still reports success -- a silent partial restore
      # for that one column. The correct fix lives at the type/coder layer
      # (stop collapsing an explicit empty hash to the same sentinel as "no
      # value") and is deliberately out of scope here.
      attrs.delete('translations') if attrs['translations'].blank?
      attrs
    end

    # A normal validated save, so model validations and the sync machinery
    # behave exactly as they do for a hand-made edit. The restore's own version
    # is stamped with the entry it came from, without dropping the request's
    # provenance metadata.
    def apply(attributes)
      info = (PaperTrail.request.controller_info || {}).dup
      metadata = (info[:metadata] || info['metadata'] || {}).dup
      metadata[:restored_from_version_id] = version.id
      info.delete('metadata')
      info[:metadata] = metadata

      PaperTrail.request(controller_info: info) do
        @record.update(attributes)
      end
    end

    def error(code, message)
      { field: ERROR_FIELD, message: message, code: code }
    end
  end
end
