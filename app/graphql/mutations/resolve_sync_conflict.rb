# frozen_string_literal: true

module Mutations
  # Resolves a SyncConflict either by keeping local values or accepting the
  # incoming source values (including accepting an upstream deletion).
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

      can_resolve = user&.admin? ||
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
        can_delete = user&.admin? ||
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

      case resolution.to_s
      when 'KEEP_LOCAL'
        apply_keep_local(conflict)
      when 'ACCEPT_INCOMING'
        apply_accept_incoming(conflict)
      end

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

    # KEEP_LOCAL: mark conflict resolved; adopt current local attrs as new snapshot.
    def apply_keep_local(conflict)
      record         = conflict.syncable
      data_source    = conflict.data_source
      source_attrs   = data_source_source_attributes(data_source, record)
      local_snapshot = record.attributes.slice(*source_attrs)

      record.update_columns(
        source_snapshot: local_snapshot,
        sync_state: 'locally_modified'
      )

      resolve_conflict!(conflict, 'keep_local')
    end

    # ACCEPT_INCOMING: apply incoming payload or soft-delete the record.
    def apply_accept_incoming(conflict)
      if conflict.conflict_type == 'source_deletion'
        apply_accept_source_deletion(conflict)
      else
        incoming = conflict.incoming_payload || {}
        denied   = incoming.keys & DENY_LIST
        raise ArgumentError, "incoming_payload contains deny-listed keys: #{denied.join(', ')}" if denied.any?

        incoming_digest = canonical_digest(incoming)
        record          = conflict.syncable

        # Full save (not update_columns): accepting upstream content is a
        # user-driven change and must be validated and PaperTrail-versioned
        # with the acting principal as whodunnit.
        record.assign_attributes(
          incoming.merge(
            'source_snapshot' => incoming,
            'source_digest' => incoming_digest,
            'sync_state' => 'synced'
          )
        )
        record.save!

        resolve_conflict!(conflict, 'accept_incoming')
      end
    end

    def apply_accept_source_deletion(conflict)
      record = conflict.syncable

      record.update!(visibility: :deleted)

      # Set deleted_by_principal_id if not already set by callback
      record.update_columns(deleted_by_principal_id: current_principal_id) unless record.deleted_by_principal_id.present?

      resolve_conflict!(conflict, 'accept_incoming')
    end

    def resolve_conflict!(conflict, resolution_value)
      conflict.update_columns(
        status: 'resolved',
        resolution: resolution_value,
        resolved_by_principal_id: current_principal_id,
        resolved_at: Time.current
      )
    end

    # Infers source_attributes from the conflict's data source (uses keys from
    # incoming_payload as a proxy -- they are exactly the source-managed attrs).
    def data_source_source_attributes(data_source, record)
      # Prefer the keys from the conflict's own incoming_payload (content conflict),
      # or fall back to source_snapshot keys on the record.
      conflict_source = SyncConflict.where(
        syncable: record,
        data_source: data_source
      ).where.not(incoming_payload: nil).first

      if conflict_source&.incoming_payload.present?
        conflict_source.incoming_payload.keys
      elsif record.source_snapshot.present?
        record.source_snapshot.keys
      else
        []
      end
    end

    def canonical_digest(hash)
      return nil if hash.nil?

      Digest::SHA256.hexdigest(JSON.generate(hash.sort.to_h))
    end
  end
end
