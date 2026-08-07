# frozen_string_literal: true

module Mutations
  # Throws away a record's pending draft. The live record is never touched, so
  # this writes no PaperTrail version: discarding an unfinished edit is not
  # something that happened to the published record.
  #
  # See PublishDraft for why `record` is the Relay Node interface.
  class DiscardDraft < BaseMutation
    # Derived from DraftableAttributes::BY_MODEL, the single real whitelist of
    # which models can hold a draft, so this can never drift from it the way a
    # hand-copied literal list did. Duplicated from PublishDraft only because
    # the two mutations may not share a concern file under this task's file
    # budget.
    DRAFTABLE_TYPES = DraftableAttributes::BY_MODEL.keys.freeze

    argument :record_id, ID,
             required: true,
             description: 'Relay global ID of the record whose draft should be discarded.'

    field :record, GraphQL::Types::Relay::Node,
          null: true,
          description: 'The live record, unchanged.'
    field :errors, [Types::MutationError], null: false

    def resolve(record_id:)
      record = load_draftable(record_id)
      authorize record, :update?

      # No draft is a no-op rather than a 404: discarding is idempotent, and a
      # second click or a stale tab must not surface an error.
      record.record_draft&.destroy!

      { record: record, errors: [] }
    end

    private

    def load_draftable(record_id)
      type_name, id = GraphQL::Schema::UniqueWithinType.decode(record_id)
      raise ActiveRecord::RecordNotFound.new(nil, type_name, nil, id) unless
        DRAFTABLE_TYPES.include?(type_name)

      Pundit.policy_scope(context[:current_user], type_name.constantize).find(id)
    rescue ArgumentError, GraphQL::ExecutionError
      # See PublishDraft#load_draftable for why both classes are rescued.
      raise GraphQL::ExecutionError.new(
        "Not Found: #{record_id} not found. The provided ID is in an invalid format.",
        extensions: { 'code' => 404 }
      )
    end
  end
end
