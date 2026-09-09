# frozen_string_literal: true

# Applies a ruling to an open SyncConflict. Shared by the resolveSyncConflict
# mutation (one conflict, an authenticated reviewer) and the fpi:resolve_conflicts
# task (a rulings file, the reviewer named in it), so the two paths cannot drift.
#
# Authorization is the caller's job; this class only changes data.
class SyncConflictResolution
  class NotOpen < StandardError; end

  DENY_LIST = SourceSynchronizer::DENY_LIST

  def initialize(conflict:, principal_id:)
    @conflict = conflict
    @principal_id = principal_id
  end

  # resolution: 'KEEP_LOCAL' or 'ACCEPT_INCOMING'
  def apply!(resolution)
    raise NotOpen, "conflict #{@conflict.id} is #{@conflict.status}" unless @conflict.status == 'open'

    case resolution.to_s
    when 'KEEP_LOCAL' then keep_local!
    when 'ACCEPT_INCOMING' then accept_incoming!
    else raise ArgumentError, "unknown resolution #{resolution.inspect}"
    end
    @conflict
  end

  # KEEP_LOCAL: mark the conflict resolved and make the kept local values stick.
  #
  # For a CONTENT conflict the new base is the INCOMING payload of the conflict
  # being resolved, not the local state. A recurring source (Food Plants
  # International, fpi-connector decision 30) re-sends the same upstream value
  # on every run: with base = local, the next run would see local unchanged
  # and incoming changed, and overwrite the value the reviewer just chose to
  # keep. With base = incoming, the next run sees incoming unchanged and local
  # changed, scores the record locally_modified, and leaves it alone until
  # upstream genuinely changes again -- which correctly raises a fresh
  # conflict. The payload is read from this conflict, never from the oldest
  # conflict of any status.
  #
  # For a SOURCE_DELETION conflict the incoming payload is empty, so the base
  # is the current local state, read through SourceSynchronizer.local_attrs
  # and NOT record.attributes.slice: Mobility keeps translated attributes in
  # the translations jsonb, and slicing #attributes wrote a snapshot with no
  # narrative fields, so a kept edit to a description could never quiesce.
  # The digest is recomputed from the same hash in both cases: a stale digest
  # reopens the conflict by another route.
  def keep_local!
    record   = @conflict.syncable
    snapshot = keep_local_base(record)

    record.update_columns(
      source_snapshot: snapshot,
      source_digest: canonical_digest(snapshot),
      sync_state: 'locally_modified'
    )
    resolve!('keep_local')
  end

  # ACCEPT_INCOMING: apply the incoming payload, or soft-delete the record for
  # a source deletion. A full save, not update_columns: accepting upstream
  # content is a person's decision and must be validated and versioned with
  # that person as whodunnit.
  def accept_incoming!
    return accept_source_deletion! if @conflict.conflict_type == 'source_deletion'

    incoming = @conflict.incoming_payload || {}
    denied   = incoming.keys & DENY_LIST
    raise ArgumentError, "incoming_payload contains deny-listed keys: #{denied.join(', ')}" if denied.any?

    record = @conflict.syncable
    record.assign_attributes(
      incoming.merge('source_snapshot' => incoming, 'source_digest' => canonical_digest(incoming), 'sync_state' => 'synced')
    )
    record.save!
    resolve!('accept_incoming')
  end

  private

  def accept_source_deletion!
    record = @conflict.syncable
    record.update!(visibility: :deleted)
    record.update_columns(deleted_by_principal_id: @principal_id) if record.deleted_by_principal_id.blank?
    resolve!('accept_incoming')
  end

  def keep_local_base(record)
    incoming = @conflict.incoming_payload
    return incoming if @conflict.conflict_type == 'content' && incoming.present?

    SourceSynchronizer.local_attrs(record, source_attributes(record))
  end

  def resolve!(resolution_value)
    @conflict.update_columns(
      status: 'resolved',
      resolution: resolution_value,
      resolved_by_principal_id: @principal_id,
      resolved_at: Time.current
    )
  end

  # The source-managed attributes, inferred from the newest content conflict's
  # incoming payload, else from the record's snapshot keys.
  def source_attributes(record)
    conflict_source = SyncConflict.where(syncable: record, data_source: @conflict.data_source)
                                  .where.not(incoming_payload: nil).first
    if conflict_source&.incoming_payload.present?
      conflict_source.incoming_payload.keys
    elsif record.source_snapshot.present?
      record.source_snapshot.keys
    else
      []
    end
  end

  def canonical_digest(hash)
    SourceSynchronizer.canonical_digest(hash)
  end
end
