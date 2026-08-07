# frozen_string_literal: true

module Drafts
  # The publish transaction: take the row lock, re-check the conflict
  # authoritatively, apply the draft, flip publication state on a first
  # publish, save once, and destroy the draft.
  #
  # ONE SAVE, ON PURPOSE. The whole point of drafts is that history shows what
  # the public actually saw, so a publish must produce exactly one PaperTrail
  # version whose changeset is the real before/after. That rules out
  # "assign, save, fix up, save again".
  #
  # WHY Drafts::Overlay RATHER THAN record.update(draft.data). The plan
  # originally said publish should "replay through the normal update path".
  # There is no such path below the mutation layer: Mutations::Concerns are
  # mutation-layer code, and a bare update misses the translations container
  # semantics entirely (merge rather than replace, the Mobility read cache, and
  # the empty-container NOT NULL trap documented on Overlay). Overlay is the
  # one reviewed implementation of all of that, so the publisher assigns
  # through it and then saves. The two things Overlay legitimately does not
  # know about -- the family_names mirror and the publication-state flip -- are
  # applied here, before the single save.
  class Publisher
    Result = Struct.new(:record, :conflicted_fields, :errors, keyword_init: true)

    def initialize(record:, force: false, access_level: nil)
      @record = record
      @force = force
      @access_level = access_level
    end

    def call
      # Named `outcome` rather than `result` so it does not shadow the private
      # #result builder that the rescue clause below has to reach.
      outcome = nil
      # with_lock reloads under SELECT ... FOR UPDATE, which is also what makes
      # the draft lookup and the conflict re-check below trustworthy: nothing
      # can write the row between the check and the save.
      @record.with_lock { outcome = publish_locked }
      outcome
    rescue ActiveRecord::StatementInvalid => e
      # A database-level rejection (a stale staged family_id, a constraint the
      # model has no validation for). The transaction has already rolled back,
      # so the draft survives; turn it into a payload error rather than a 500.
      # Only the exception class is surfaced -- the message can carry row data.
      @record.errors.add(:base, "could not be published (#{e.class})")
      result
    end

    private

    def publish_locked
      draft = @record.record_draft
      return result if draft.blank?

      # The check at dialog-open time is advisory. This one is authoritative:
      # it runs inside the row lock, so nothing can slip in between.
      conflicts = ConflictDetector.new(draft).conflicted_fields
      return result(conflicts) if conflicts.any? && !@force

      apply(draft)
      # Deliberately does NOT destroy the draft on failure. A failed publish
      # must never lose work.
      return result unless @record.save

      draft.destroy!
      result
    end

    def apply(draft)
      Overlay.apply(@record, draft)
      apply_family_names_mirror(draft)
      apply_publication_state
      keep_container_savable
    end

    # Mutations::Concerns::FamilyAssignment#apply_family fills the legacy
    # free-text family_names column from the assigned family, but only when it
    # is blank -- whatever a human typed stays authoritative. That concern is
    # mutation-layer code and does not run here, so publishing a draft that
    # stages family_id has to reproduce it or the mirror would silently apply
    # to direct edits and not to published ones.
    #
    # Keyed on the draft having staged family_id at all (not on the value being
    # present), mirroring apply_family's `attributes.key?(:family)` idiom: a
    # staged nil is a real clear, and clearing the family must not invent a name.
    def apply_family_names_mirror(draft)
      return unless DraftableAttributes.for(@record.class).include?('family_id')
      return unless draft.data.key?('family_id')

      family = @record.family
      @record.family_names = family.name if family && @record.family_names.blank?
    end

    # First publish flips draft -> published. Family is pure reference data with
    # no OrganizedResource, hence the respond_to? guard, which covers
    # access_level too since both come from that concern.
    #
    # The legacy `visibility` integer is NEVER assigned here: OrganizedResource's
    # before_save dual-write recomputes it from the trio, and setting both would
    # make the two writes race for precedence inside that callback.
    def apply_publication_state
      return unless @record.respond_to?(:publication_state)

      @record.publication_state = 'published' if @record.publication_state == 'draft'
      @record.access_level = @access_level if @access_level.present?
    end

    # Defence in depth against the empty-container trap. `translations` is
    # jsonb NOT NULL, and Type::Serialized writes an exactly-empty container as
    # SQL NULL, so a record holding {} cannot be saved. Drafts::Overlay already
    # guarantees this for the container it assigns; this covers the assignment
    # it did not make (a record loaded with {} already, or a future writer added
    # to apply). Re-seeding must be an in-place mutation: re-assigning would
    # cast, strip and empty it again.
    def keep_container_savable
      return unless @record.respond_to?(:translations)
      return unless @record.translations.is_a?(Hash) && @record.translations.empty?

      @record.translations[Mobility.locale.to_s] ||= {}
    end

    # `errors` is always the record's own ActiveModel::Errors: empty on a clean
    # publish, populated after a rejected save, and empty again on a conflict
    # (a conflict is not an error, it is an answer). The mutation formats it.
    def result(conflicted_fields = [])
      Result.new(record: @record, conflicted_fields: conflicted_fields, errors: @record.errors)
    end
  end
end
