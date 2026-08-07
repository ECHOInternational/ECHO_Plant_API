# frozen_string_literal: true

# Gives a model its optional working copy. Included by the four models that
# have translatable fields and an editing surface worth staging.
module Draftable
  extend ActiveSupport::Concern

  included do
    has_one :record_draft, as: :draftable, dependent: :destroy
  end

  # True when a published version exists AND there are staged changes. Drives
  # the "Published - edited" status. Derived, never stored: Wagtail keeps a
  # has_unpublished_changes column, and a stored flag is one more thing that can
  # drift from reality.
  def pending_changes?
    record_draft.present?
  end

  def draftable_attribute_names
    DraftableAttributes.for(self.class)
  end
end
