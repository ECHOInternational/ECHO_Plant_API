# frozen_string_literal: true

# A working copy of a record's own columns, held off the live row so an
# unfinished edit does not force the record out of public view.
#
# Deliberately NOT versioned. ApplicationRecord calls has_paper_trail on every
# model; drafts must opt out, because a draft save is not something that
# happened to the live record. Storing drafts IN PaperTrail was considered and
# rejected -- see docs/superpowers/specs/2026-08-07-draft-publish-design.md.
class RecordDraft < ApplicationRecord
  # Disables the inherited has_paper_trail for this model only.
  #
  # Neither documented PaperTrail 17 opt-out reads on ApplicationRecord's
  # subclasses: `paper_trail.disable` is request-scoped (PaperTrail::Request,
  # backed by RequestStore) and has no class-level equivalent, and calling
  # `has_paper_trail` again (even with `on: []`) raises "has_paper_trail must
  # be called only once" because RecordDraft already inherits
  # PaperTrail::Model::InstanceMethods from ApplicationRecord's call. Instead,
  # override the inherited `paper_trail_options` (a `class_attribute`, so this
  # assignment is scoped to RecordDraft and its subclasses only) with an
  # `:unless` guard that every create/update/destroy callback consults via
  # `save_version?` before writing a version. Covered by
  # spec/models/record_draft_spec.rb, because the failure mode is silent.
  self.paper_trail_options = paper_trail_options.merge(unless: ->(_) { true })

  belongs_to :draftable, polymorphic: true

  belongs_to :author, class_name: 'Principal', foreign_key: :author_principal_id, inverse_of: false
  belongs_to :last_editor, class_name: 'Principal', foreign_key: :last_editor_principal_id,
                           inverse_of: false

  validates :base_updated_at, presence: true

  # The attribute names this draft changes. Drives the changed-field markers,
  # the history-drawer entry, and conflict detection.
  def changed_fields
    data.keys
  end
end
