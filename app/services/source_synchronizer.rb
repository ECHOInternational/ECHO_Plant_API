# frozen_string_literal: true

require 'digest'

# Applies an incoming batch of records from an external source system using
# three-way comparison logic (base vs. local vs. incoming).
#
# Usage:
#   SourceSynchronizer.new(
#     data_source:       <DataSource>,
#     model:             Plant,
#     source_attributes: %w[scientific_name family_names],
#     run_id:            "run-abc-123"
#   ).apply(incoming)
#
# Where +incoming+ is an array of hashes with keys:
#   source_record_id: String
#   deleted:          Boolean
#   attributes:       Hash  (source-managed attribute values, string-keyed)
#   source_updated_at: Time
#
# Returns a RunReport struct.
class SourceSynchronizer
  # Attributes that are never allowed in source_attributes (auth/workflow state).
  DENY_LIST = %w[
    id
    visibility
    publication_state
    access_level
    deleted_at
    deleted_by_principal_id
    owned_by
    created_by
    owner_organization_id
    source_organization_id
    created_by_principal_id
    data_source_id
    source_record_id
    source_updated_at
    last_synced_at
    source_digest
    source_snapshot
    sync_state
    created_at
    updated_at
  ].freeze

  RunReport = Struct.new(
    :synced,
    :applied,
    :locally_modified,
    :conflicts_created,
    :conflicts_updated,
    :source_deletion_conflicts,
    :tombstone_kept,
    :created,
    :invalid,
    :unknown_deleted,
    :invalid_details,
    keyword_init: true
  ) do
    def initialize(**)
      super
      self.synced                   ||= 0
      self.applied                  ||= 0
      self.locally_modified         ||= 0
      self.conflicts_created        ||= 0
      self.conflicts_updated        ||= 0
      self.source_deletion_conflicts ||= 0
      self.tombstone_kept           ||= 0
      self.created                  ||= 0
      self.invalid                  ||= 0
      self.unknown_deleted          ||= 0
      self.invalid_details          ||= []
    end
  end

  def initialize(data_source:, model:, source_attributes:, run_id:)
    @data_source       = data_source
    @model             = model
    @run_id            = run_id
    @source_attributes = Array(source_attributes).map(&:to_s).freeze

    denied = @source_attributes & DENY_LIST
    raise ArgumentError, "source_attributes intersects deny-list: #{denied.join(', ')}" if denied.any?
  end

  # Processes the batch. Each row is handled independently.
  # Returns a RunReport.
  def apply(incoming)
    report = RunReport.new
    svc_principal = @data_source.service_principal!

    PaperTrail.request(
      whodunnit: svc_principal.id,
      controller_info: {
        metadata: {
          origin: 'sync',
          data_source_id: @data_source.id,
          sync_run_id: @run_id
        }
      }
    ) do
      incoming.each do |row|
        process_row(row, report)
      end
    end

    report
  end

  private

  def process_row(row, report)
    src_id   = row[:source_record_id]
    deleted  = row[:deleted]
    attrs    = row[:attributes] || {}
    src_at   = row[:source_updated_at]

    incoming_attrs = attrs.stringify_keys.slice(*@source_attributes)
    record = find_record(src_id)

    if record.nil?
      if deleted
        report.unknown_deleted += 1
      else
        create_record(src_id, incoming_attrs, src_at, report)
      end
      return
    end

    # Tombstone wins: if locally deleted, do nothing regardless of upstream
    if record.deleted_at.present? && !deleted
      report.tombstone_kept += 1
      return
    end

    # Upstream deletion: create/refresh source_deletion conflict
    if deleted
      handle_source_deletion(record, report)
      return
    end

    compare_and_sync(record, incoming_attrs, src_at, report)
  end

  def find_record(src_id)
    @model.find_by(data_source_id: @data_source.id, source_record_id: src_id)
  end

  # rubocop:disable Metrics/MethodLength
  def compare_and_sync(record, incoming_attrs, src_at, report)
    base  = base_attrs(record)
    local = record.attributes.slice(*@source_attributes)

    local_digest    = canonical_digest(local)
    incoming_digest = canonical_digest(incoming_attrs)

    if base.nil?
      # First sync of a pre-existing record.
      # Conservative: treat local as unchanged ONLY when local == incoming.
      if local_digest == incoming_digest
        record.update_columns(
          'source_snapshot' => local,
          'source_digest' => local_digest,
          'source_updated_at' => src_at,
          'last_synced_at' => Time.current,
          'sync_state' => 'synced'
        )
        report.synced += 1
      else
        # Local diverges from incoming and there is no base to arbitrate.
        # Settled rule: never silently choose one side -- surface a reviewable
        # conflict with an empty base payload marking the first-sync case.
        handle_content_conflict(record, {}, local, incoming_attrs, report)
      end
      return
    end

    base_digest      = canonical_digest(base)
    local_changed    = base_digest != local_digest
    incoming_changed = base_digest != incoming_digest

    if !local_changed && !incoming_changed
      # unchanged / unchanged -- touch only
      record.update_columns(
        last_synced_at: Time.current,
        sync_state: 'synced'
      )
      report.synced += 1

    elsif !local_changed && incoming_changed
      # unchanged / incoming changed -- apply incoming through a full save so
      # the change is validated and PaperTrail-versioned with the sync
      # attribution (whodunnit = service principal, metadata origin 'sync').
      record.assign_attributes(
        incoming_attrs.merge(
          'source_snapshot' => incoming_attrs,
          'source_digest' => incoming_digest,
          'source_updated_at' => src_at,
          'last_synced_at' => Time.current,
          'sync_state' => 'synced'
        )
      )
      begin
        record.save!
        report.applied += 1
      rescue ActiveRecord::RecordInvalid => e
        record.reload
        report.invalid += 1
        report.invalid_details << {
          source_record_id: record.source_record_id,
          error: e.message
        }
      end

    elsif local_changed && !incoming_changed
      # local changed / incoming unchanged -- keep local
      record.update_columns(
        last_synced_at: Time.current,
        sync_state: 'locally_modified'
      )
      report.locally_modified += 1

    else
      # both changed -- conflict
      handle_content_conflict(record, base, local, incoming_attrs, report)
    end
  end
  # rubocop:enable Metrics/MethodLength

  # base = last accepted source snapshot, sliced to source_attributes
  def base_attrs(record)
    snap = record.source_snapshot
    return nil if snap.nil?

    snap.slice(*@source_attributes)
  end

  def handle_content_conflict(record, base, local, incoming_attrs, report)
    existing = SyncConflict.where(
      syncable: record,
      conflict_type: 'content',
      status: 'open'
    ).first

    if existing
      existing.update_columns(
        incoming_payload: incoming_attrs,
        sync_run_id: @run_id
      )
      report.conflicts_updated += 1
    else
      SyncConflict.create!(
        syncable: record,
        data_source: @data_source,
        conflict_type: 'content',
        status: 'open',
        base_payload: base,
        local_payload: local,
        incoming_payload: incoming_attrs,
        sync_run_id: @run_id
      )
      report.conflicts_created += 1
    end

    record.update_columns(
      last_synced_at: Time.current,
      sync_state: 'conflict'
    )
  end

  def handle_source_deletion(record, report)
    local = record.attributes.slice(*@source_attributes)

    existing = SyncConflict.where(
      syncable: record,
      conflict_type: 'source_deletion',
      status: 'open'
    ).first

    if existing
      existing.update_columns(
        local_payload: local,
        incoming_payload: {},
        sync_run_id: @run_id
      )
    else
      SyncConflict.create!(
        syncable: record,
        data_source: @data_source,
        conflict_type: 'source_deletion',
        status: 'open',
        base_payload: base_attrs(record),
        local_payload: local,
        incoming_payload: {},
        sync_run_id: @run_id
      )
    end

    # Always count as a source_deletion conflict (new or refreshed)
    report.source_deletion_conflicts += 1

    record.update_columns(
      last_synced_at: Time.current,
      sync_state: 'conflict'
    )
  end

  def create_record(src_id, incoming_attrs, src_at, report)
    svc_principal = @data_source.service_principal!
    incoming_digest = canonical_digest(incoming_attrs)
    org_id = @data_source.organization_id

    record = @model.new(
      incoming_attrs.merge(
        owner_organization_id: org_id,
        source_organization_id: org_id,
        created_by_principal_id: svc_principal.id,
        created_by: svc_principal.email,
        owned_by: svc_principal.email,
        data_source_id: @data_source.id,
        source_record_id: src_id,
        source_updated_at: src_at,
        last_synced_at: Time.current,
        source_digest: incoming_digest,
        source_snapshot: incoming_attrs,
        sync_state: 'synced',
        visibility: :private
      )
    )

    if record.save
      report.created += 1
    else
      report.invalid += 1
      report.invalid_details << {
        source_record_id: src_id,
        error: record.errors.full_messages.join('; ')
      }
    end
  end

  # Canonical digest of a hash: SHA256 of JSON with sorted keys.
  # Returns nil for a nil hash.
  def canonical_digest(hash)
    return nil if hash.nil?

    Digest::SHA256.hexdigest(JSON.generate(hash.sort.to_h))
  end
end
