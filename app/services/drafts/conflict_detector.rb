# frozen_string_literal: true

module Drafts
  # Answers "did the live record change, under this draft, in a field the draft
  # also changes?"
  #
  # This is the one place PaperTrail is used by the drafts feature, and it is
  # the use PaperTrail is actually for: an immutable record of what happened to
  # the live row. Storing drafts in it was rejected; reading it to detect
  # collisions is exactly right.
  #
  # Field-level rather than timestamp-level on purpose. SourceSynchronizer,
  # ChangeHistory::Restorer, mobile and direct API callers can all move live
  # under a draft, and several of them touch bookkeeping columns on every run.
  # A coarse updated_at comparison would fire constantly and teach editors to
  # dismiss the warning.
  class ConflictDetector
    def initialize(draft)
      @draft = draft
    end

    def conflicted_fields
      return [] if @draft.blank?

      (live_changed_fields & @draft.changed_fields).sort
    end

    private

    def live_changed_fields
      versions = PaperTrail::Version
                 .where(item_type: @draft.draftable_type, item_id: @draft.draftable_id)
                 .where('created_at > ?', @draft.base_updated_at)

      versions.flat_map { |version| version_changed_fields(version) }.uniq
    end

    # A changeset that cannot be deserialized must not take down a page load or
    # block a publish. Rescuing here, per version, rather than around the whole
    # flat_map, keeps the fail-open as narrow as possible: one bad version's
    # changeset is skipped and treated as "no detectable conflict" for those
    # keys, but every other version in the range still contributes its real
    # changes. A wider rescue would silently blank the entire result -- and
    # therefore report no conflict at all -- for one corrupt row. The publish
    # still runs inside with_lock either way, and nothing is lost because
    # recordHistory keeps the overwritten value.
    def version_changed_fields(version)
      (version.changeset || {}).keys
    rescue StandardError
      []
    end
  end
end
