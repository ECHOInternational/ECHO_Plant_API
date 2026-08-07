# frozen_string_literal: true

module Types
  module Concerns
    # The `draft` metadata field, included by the four draftable types.
    # Deliberately no `data` field: staged values are read through the
    # perspective lens, not merged client-side.
    module DraftFields
      def self.included(base)
        base.field :draft, Types::RecordDraftInfoType,
                   null: true,
                   description: 'Pending staged changes, or null. Visible only to users who may edit.'
      end

      def draft
        return nil unless Pundit.policy(context[:current_user], object).update?

        object.record_draft
      end
    end
  end
end
