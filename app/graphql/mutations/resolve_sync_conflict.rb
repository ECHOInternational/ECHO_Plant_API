# frozen_string_literal: true

module Mutations
  # Resolves a SyncConflict either by keeping local values or accepting the
  # incoming source values (including accepting an upstream deletion).
  #
  # Authorization lives here; the data change is SyncConflictResolution, which
  # the fpi:resolve_conflicts task shares so a bulk ruling and a one-off
  # ruling can never diverge.
  class ResolveSyncConflict < BaseMutation
    DENY_LIST = SourceSynchronizer::DENY_LIST

    argument :conflict_id, ID,
             required: true,
             description: 'Relay global ID of the SyncConflict to resolve.'
    argument :resolution, Types::SyncConflictResolutionEnum,
             required: true,
             description: 'How to resolve the conflict.'

    field :sync_conflict, Types::SyncConflictType, null: true
    field :errors,        [Types::MutationError],  null: false

    def authorized?(conflict_id:, resolution:)
      conflict = load_conflict!(conflict_id)
      record   = conflict.syncable

      owner_org_id = record.owner_organization_id
      user         = context[:current_user]

      can_resolve = user&.super_admin? ||
                    user&.system_superuser? ||
                    user&.organization_capability?(owner_org_id, :resolve_conflicts)

      unless can_resolve
        raise Pundit::NotAuthorizedError.new(
          query: :resolve_conflicts,
          record: conflict,
          policy: nil
        )
      end

      if resolution.to_s == 'ACCEPT_INCOMING' && conflict.conflict_type == 'source_deletion'
        can_delete = user&.super_admin? ||
                     user&.system_superuser? ||
                     user&.organization_capability?(owner_org_id, :accept_source_deletion)

        unless can_delete
          raise Pundit::NotAuthorizedError.new(
            query: :accept_source_deletion,
            record: conflict,
            policy: nil
          )
        end
      end

      true
    end

    def resolve(conflict_id:, resolution:)
      conflict = load_conflict!(conflict_id)

      if conflict.status != 'open'
        return {
          sync_conflict: nil,
          errors: [{
            field: 'conflictId',
            message: 'Conflict is already resolved.',
            code: 400
          }]
        }
      end

      SyncConflictResolution.new(conflict: conflict, principal_id: current_principal_id).apply!(resolution)

      { sync_conflict: conflict, errors: [] }
    end

    private

    def load_conflict!(conflict_id)
      _type, raw_id = GraphQL::Schema::UniqueWithinType.decode(conflict_id)
      SyncConflict.find(raw_id)
    rescue ActiveRecord::RecordNotFound, ArgumentError
      raise GraphQL::ExecutionError.new(
        "Not Found: SyncConflict #{conflict_id} not found.",
        extensions: { 'code' => 404 }
      )
    end

    def current_principal_id
      context[:current_user]&.principal&.id
    end
  end
end
