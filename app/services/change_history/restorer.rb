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
      # `translations` is NOT NULL with a `{}` default. When the live record's
      # translations column has never been explicitly written (still exactly
      # that schema default, so it never entered ActiveRecord's dirty-tracking
      # set for any save), PaperTrail's captured snapshot carries either a bare
      # nil OR a "correct-looking" empty {} for it (observed both, verified
      # against the real dev server) -- there is no real "before" content
      # either way. Writing a literal nil violates the NOT NULL constraint
      # outright, and -- less obviously -- even writing an explicit {} through
      # Mobility's container-backend writer hits a known cache/dirty-tracking
      # defect (see config/application.rb's partial_inserts comment) that can
      # *also* persist nil despite the assigned value. Dropping the key
      # whenever the captured value is blank (nil or {}) sidesteps both: Rails'
      # partial writes then simply never touch the column, leaving its current
      # (already correct) value alone. A record that genuinely has translated
      # content reifies a non-blank hash and is unaffected -- that write still
      # goes through normally.
      attrs.delete('translations') if attrs.key?('translations') && attrs['translations'].blank?
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
