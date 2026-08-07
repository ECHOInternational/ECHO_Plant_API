# frozen_string_literal: true

module Mutations
  # Applies a record's pending draft to the live record.
  #
  # Payload type choice: `record` is the Relay Node interface rather than a
  # union. Plant, Variety, Family and Category all `implements
  # GraphQL::Types::Relay::Node`, PlantApiSchema.resolve_type already resolves
  # all four, and QueryType's node/nodes fields prove the pattern in this
  # schema. Types::OwnedRecordUnion cannot be reused: it deliberately covers
  # the five independently-owned models and Family is not one of them, while
  # Specimen and Location are, and neither is draftable. Adding a fifth
  # possible type to it would be wrong, and a new union type would be a fifth
  # near-identical polymorphic wrapper for no gain.
  class PublishDraft < BaseMutation
    # Derived from DraftableAttributes::BY_MODEL, the single real whitelist of
    # which models can hold a draft, so this can never drift from it the way a
    # hand-copied literal list did. Duplicated in DiscardDraft only because the
    # two mutations may not share a concern file under this task's file budget.
    DRAFTABLE_TYPES = DraftableAttributes::BY_MODEL.keys.freeze

    argument :record_id, ID,
             required: true,
             description: 'Relay global ID of the record whose draft should be published.'
    argument :access_level, Types::AccessLevelEnum,
             required: false,
             description: 'Access level to publish at. Chiefly meaningful on a first publish; ' \
                          'omitted, the record keeps the access level it already has.'
    argument :force, Boolean,
             required: false,
             default_value: false,
             description: 'Publish even though the live record changed under this draft.'

    field :record, GraphQL::Types::Relay::Node,
          null: true,
          description: 'The record as it now stands. On a refusal by conflict (conflictedFields non-empty) ' \
                       'this is the untouched live record. On a refusal by validation failure this is the ' \
                       'in-memory record with the draft values applied but NOT saved -- do not treat its ' \
                       'presence or shape as confirmation of what was persisted. `errors` is the authoritative ' \
                       'signal for whether the publish succeeded.'
    field :conflicted_fields, [String],
          null: false,
          description: 'Fields the live record changed under this draft. Non-empty means nothing was published; ' \
                       'retry with force to publish anyway.'
    field :errors, [Types::MutationError], null: false

    def resolve(record_id:, access_level: nil, force: false)
      record = load_draftable(record_id)
      authorize record, :update?

      result = Drafts::Publisher.new(record: record, force: force, access_level: access_level).call

      {
        record: result.record,
        conflicted_fields: result.conflicted_fields,
        errors: errors_from_active_record(result.errors)
      }
    end

    private

    # Decodes the global ID and confirms the type can actually hold a draft, so
    # a Specimen or Location ID produces a clean 404 rather than a NoMethodError
    # deeper in the publisher.
    def load_draftable(record_id)
      type_name, id = GraphQL::Schema::UniqueWithinType.decode(record_id)
      raise ActiveRecord::RecordNotFound.new(nil, type_name, nil, id) unless
        DRAFTABLE_TYPES.include?(type_name)

      Pundit.policy_scope(context[:current_user], type_name.constantize).find(id)
    rescue ArgumentError, GraphQL::ExecutionError
      # A malformed global ID. graphql-ruby's base64 decoder raises
      # ArgumentError in some versions and wraps it as a bare
      # GraphQL::ExecutionError with no extensions.code in others, so both are
      # rescued -- the same dual-class rescue QueryType#decode_global_id uses
      # to keep the coded-404 contract.
      raise GraphQL::ExecutionError.new(
        "Not Found: #{record_id} not found. The provided ID is in an invalid format.",
        extensions: { 'code' => 404 }
      )
    end
  end
end
