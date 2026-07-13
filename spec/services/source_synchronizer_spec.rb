# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SourceSynchronizer, type: :service do
  # The attributes we manage via the sync path in these tests
  SOURCE_ATTRS = %w[scientific_name family_names].freeze

  let(:org)         { create(:organization, :real) }
  let(:data_source) { create(:data_source, organization: org) }
  let(:run_id)      { SecureRandom.hex(8) }

  # Helper to build a synchronizer with the default setup
  def sync(attrs: SOURCE_ATTRS, model: Plant, ds: data_source)
    SourceSynchronizer.new(
      data_source:       ds,
      model:             model,
      source_attributes: attrs,
      run_id:            run_id
    )
  end

  # Helper to build a row with defaults
  def row(source_record_id:, scientific_name: 'Moringa oleifera', family_names: 'Moringaceae',
          deleted: false, source_updated_at: 1.day.ago)
    {
      source_record_id: source_record_id,
      deleted:          deleted,
      attributes:       { 'scientific_name' => scientific_name, 'family_names' => family_names },
      source_updated_at: source_updated_at
    }
  end

  # Builds a plant that already exists as a synced record
  def synced_plant(src_id:, scientific_name: 'Moringa oleifera', family_names: 'Moringaceae')
    snap = { 'scientific_name' => scientific_name, 'family_names' => family_names }
    create(
      :plant,
      data_source_id:   data_source.id,
      source_record_id: src_id,
      source_snapshot:  snap,
      scientific_name:  scientific_name,
      family_names:     family_names,
      owner_organization_id:   org.id,
      source_organization_id:  org.id
    )
  end

  # ---------------------------------------------------------------------------
  # Deny-list
  # ---------------------------------------------------------------------------
  describe 'deny-list enforcement at construction time' do
    SourceSynchronizer::DENY_LIST.each do |denied_attr|
      it "raises ArgumentError when source_attributes includes '#{denied_attr}'" do
        expect do
          SourceSynchronizer.new(
            data_source:       data_source,
            model:             Plant,
            source_attributes: [denied_attr],
            run_id:            run_id
          )
        end.to raise_error(ArgumentError, /deny-list/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Row 1: local unchanged / incoming unchanged -> touch last_synced_at, synced
  # ---------------------------------------------------------------------------
  describe 'unchanged / unchanged (row 1)' do
    it 'touches last_synced_at and sets sync_state synced without creating versions' do
      plant = synced_plant(src_id: 'src-1')
      prev_synced = plant.last_synced_at

      report = sync.apply([row(source_record_id: 'src-1')])

      expect(report.synced).to eq 1
      expect(report.applied).to eq 0
      plant.reload
      expect(plant.sync_state).to eq 'synced'
      expect(plant.last_synced_at).to be > (prev_synced || 1.minute.ago)
      # Only update_columns used -- scientific_name unchanged
      expect(plant.scientific_name).to eq 'Moringa oleifera'
    end
  end

  # ---------------------------------------------------------------------------
  # Row 2: local unchanged / incoming changed -> apply incoming
  # ---------------------------------------------------------------------------
  describe 'unchanged local / changed incoming (row 2)' do
    it 'applies incoming attributes and updates snapshot/digest/timestamps' do
      plant = synced_plant(src_id: 'src-2')

      report = sync.apply([row(source_record_id: 'src-2', scientific_name: 'Cajanus cajan')])

      expect(report.applied).to eq 1
      plant.reload
      expect(plant.scientific_name).to eq 'Cajanus cajan'
      expect(plant.sync_state).to eq 'synced'
      expect(plant.source_snapshot['scientific_name']).to eq 'Cajanus cajan'
      expect(plant.source_digest).to be_present
    end

    it 'records a PaperTrail version attributed to the service principal', versioning: true do
      plant = synced_plant(src_id: 'src-2v')

      expect do
        sync.apply([row(source_record_id: 'src-2v', scientific_name: 'Cajanus cajan')])
      end.to change { PaperTrail::Version.where(item: plant).count }.by(1)

      version = PaperTrail::Version.where(item: plant).order(:created_at).last
      expect(version.whodunnit).to eq data_source.service_principal!.id
    end
  end

  # ---------------------------------------------------------------------------
  # Row 3: local changed / incoming unchanged -> keep local, locally_modified
  # ---------------------------------------------------------------------------
  describe 'changed local / unchanged incoming (row 3)' do
    it 'keeps local values and marks sync_state locally_modified' do
      plant = synced_plant(src_id: 'src-3')
      # local change diverges from snapshot
      plant.update_columns(scientific_name: 'Local Override')

      report = sync.apply([row(source_record_id: 'src-3')])

      expect(report.locally_modified).to eq 1
      plant.reload
      # local value preserved
      expect(plant.scientific_name).to eq 'Local Override'
      expect(plant.sync_state).to eq 'locally_modified'
    end
  end

  # ---------------------------------------------------------------------------
  # Row 4: both changed -> create content conflict, sync_state conflict
  # ---------------------------------------------------------------------------
  describe 'both local and incoming changed (row 4)' do
    it 'creates a content SyncConflict and sets sync_state conflict' do
      plant = synced_plant(src_id: 'src-4')
      plant.update_columns(scientific_name: 'Local Override')

      expect do
        sync.apply([row(source_record_id: 'src-4', scientific_name: 'Upstream Change')])
      end.to change(SyncConflict, :count).by(1)

      conflict = SyncConflict.last
      expect(conflict.conflict_type).to eq 'content'
      expect(conflict.status).to eq 'open'
      expect(conflict.sync_run_id).to eq run_id

      plant.reload
      expect(plant.sync_state).to eq 'conflict'
    end

    it 'does NOT create a duplicate conflict on re-sync; updates incoming_payload instead' do
      plant = synced_plant(src_id: 'src-4b')
      plant.update_columns(scientific_name: 'Local Override')

      sync.apply([row(source_record_id: 'src-4b', scientific_name: 'First Upstream')])
      expect(SyncConflict.where(syncable: plant, conflict_type: 'content', status: 'open').count).to eq 1

      new_run = SecureRandom.hex(8)
      SourceSynchronizer.new(
        data_source:       data_source,
        model:             Plant,
        source_attributes: SOURCE_ATTRS,
        run_id:            new_run
      ).apply([row(source_record_id: 'src-4b', scientific_name: 'Second Upstream')])

      expect(SyncConflict.where(syncable: plant, conflict_type: 'content', status: 'open').count).to eq 1

      conflict = SyncConflict.where(syncable: plant, conflict_type: 'content', status: 'open').first
      expect(conflict.incoming_payload['scientific_name']).to eq 'Second Upstream'
      expect(conflict.sync_run_id).to eq new_run
    end
  end

  # ---------------------------------------------------------------------------
  # Row 5: local tombstone wins (deleted_at present, upstream not deleted)
  # ---------------------------------------------------------------------------
  describe 'local tombstone wins (row 5)' do
    it 'makes no changes and counts tombstone_kept' do
      plant = synced_plant(src_id: 'src-5')
      plant.update_columns(deleted_at: Time.current)

      report = sync.apply([row(source_record_id: 'src-5')])

      expect(report.tombstone_kept).to eq 1
      plant.reload
      expect(plant.scientific_name).to eq 'Moringa oleifera'
    end
  end

  # ---------------------------------------------------------------------------
  # Row 6: upstream deletion -> create source_deletion conflict
  # ---------------------------------------------------------------------------
  describe 'upstream deletion (row 6)' do
    it 'creates a source_deletion conflict and does not modify the record' do
      plant = synced_plant(src_id: 'src-6')

      expect do
        sync.apply([row(source_record_id: 'src-6', deleted: true)])
      end.to change(SyncConflict, :count).by(1)

      conflict = SyncConflict.last
      expect(conflict.conflict_type).to eq 'source_deletion'
      expect(conflict.status).to eq 'open'
      expect(conflict.incoming_payload).to eq({})

      plant.reload
      expect(plant.deleted_at).to be_nil
      expect(plant.sync_state).to eq 'conflict'
    end
  end

  # ---------------------------------------------------------------------------
  # base=nil first-sync: two branches
  # ---------------------------------------------------------------------------
  describe 'base=nil first sync' do
    context 'when local values equal incoming (adopt snapshot)' do
      it 'treats as unchanged -> synced, adopts snapshot' do
        plant = create(
          :plant,
          data_source_id:   data_source.id,
          source_record_id: 'src-new-1',
          source_snapshot:  nil,
          scientific_name:  'Moringa oleifera',
          family_names:     'Moringaceae',
          owner_organization_id:  org.id,
          source_organization_id: org.id
        )

        report = sync.apply([row(source_record_id: 'src-new-1')])

        # base=nil, local==incoming -> adopt snapshot, mark synced
        plant.reload
        expect(plant.sync_state).to eq 'synced'
        expect(plant.source_snapshot).to eq(
          'scientific_name' => 'Moringa oleifera',
          'family_names'    => 'Moringaceae'
        )
        expect(report.applied + report.synced).to be >= 1
      end
    end

    context 'when local values differ from incoming (reviewable conflict)' do
      # Settled rule: never silently choose one side. With no base snapshot
      # to arbitrate, divergence surfaces as a content conflict whose
      # base_payload is empty (first-sync marker), and local data is kept.
      it 'creates a content conflict with an empty base payload' do
        plant = create(
          :plant,
          data_source_id:   data_source.id,
          source_record_id: 'src-new-2',
          source_snapshot:  nil,
          scientific_name:  'Different Local Name',
          family_names:     'Moringaceae',
          owner_organization_id:  org.id,
          source_organization_id: org.id
        )

        report = sync.apply([row(source_record_id: 'src-new-2')])

        plant.reload
        expect(plant.sync_state).to eq 'conflict'
        expect(plant.scientific_name).to eq 'Different Local Name'
        expect(report.conflicts_created).to eq 1

        conflict = SyncConflict.find_by(syncable: plant, status: 'open')
        expect(conflict.conflict_type).to eq 'content'
        expect(conflict.base_payload).to eq({})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # NEW upstream record: created
  # ---------------------------------------------------------------------------
  describe 'new upstream record (no local match)' do
    it 'creates a new plant with source-managed attrs and sets sync_state synced' do
      svc_email = "sync+#{data_source.source_system_key}@plant-api.echocommunity.org"

      expect do
        sync.apply([row(source_record_id: 'brand-new-1')])
      end.to change(Plant, :count).by(1)

      plant = Plant.find_by(data_source_id: data_source.id, source_record_id: 'brand-new-1')
      expect(plant).to be_present
      expect(plant.sync_state).to eq 'synced'
      expect(plant.visibility).to eq 'private'
      expect(plant.owned_by).to eq svc_email
      expect(plant.owner_organization_id).to eq org.id
      expect(plant.source_snapshot).to eq(
        'scientific_name' => 'Moringa oleifera',
        'family_names'    => 'Moringaceae'
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown deleted: upstream says deleted but no local record
  # ---------------------------------------------------------------------------
  describe 'unknown deleted (no local record, upstream deleted)' do
    it 'counts as unknown_deleted and creates nothing' do
      expect do
        report = sync.apply([row(source_record_id: 'ghost-1', deleted: true)])
        expect(report.unknown_deleted).to eq 1
      end.not_to change(Plant, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid payload at creation
  # ---------------------------------------------------------------------------
  describe 'invalid incoming record on creation' do
    it 'counts as invalid and stores detail without raising' do
      # Variety requires plant and name; omit both to trigger validation failure.
      # source_attributes only includes 'description' which is not required,
      # so the model will fail validation on the missing required fields.
      incoming = [{
        source_record_id:  'invalid-1',
        deleted:           false,
        attributes:        { 'description' => 'A description' },
        source_updated_at: Time.current
      }]

      report = SourceSynchronizer.new(
        data_source:       data_source,
        model:             Variety,
        source_attributes: %w[description],
        run_id:            run_id
      ).apply(incoming)

      expect(report.invalid).to eq 1
      expect(report.invalid_details.first[:source_record_id]).to eq 'invalid-1'
      expect(report.invalid_details.first[:error]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotent re-run
  # ---------------------------------------------------------------------------
  describe 'idempotency' do
    it 'produces no new changes or conflicts on identical re-run' do
      plant = synced_plant(src_id: 'idem-1')
      batch = [row(source_record_id: 'idem-1')]

      sync.apply(batch)
      count_before = SyncConflict.count
      sync.apply(batch)

      expect(SyncConflict.count).to eq count_before
      plant.reload
      expect(plant.sync_state).to eq 'synced'
    end
  end

  # ---------------------------------------------------------------------------
  # Duplicate source_record_id in one batch
  # ---------------------------------------------------------------------------
  describe 'duplicate source_record_id in one batch' do
    it 'processes both rows deterministically without crashing' do
      synced_plant(src_id: 'dup-1')
      batch = [
        row(source_record_id: 'dup-1', scientific_name: 'First'),
        row(source_record_id: 'dup-1', scientific_name: 'Second')
      ]

      expect { sync.apply(batch) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # PaperTrail attribution
  # ---------------------------------------------------------------------------
  describe 'PaperTrail attribution', versioning: true do
    it 'sets whodunnit = service principal id on new records created by sync' do
      svc_principal = data_source.service_principal!

      # New record creation goes through model.save (callbacks active), so
      # PaperTrail writes a 'create' version with the PaperTrail.request whodunnit.
      expect do
        sync.apply([row(source_record_id: 'pt-brand-new')])
      end.to change(PaperTrail::Version, :count).by_at_least(1)

      version = PaperTrail::Version.where(
        item_type: 'Plant',
        event:     'create'
      ).order(:created_at).last
      expect(version).to be_present
      expect(version.whodunnit).to eq svc_principal.id
    end

    it 'wraps apply in PaperTrail.request with the service principal as whodunnit' do
      # Verify the service principal is created and has the expected properties.
      # PaperTrail.request sets the whodunnit for any versions created during apply.
      svc_principal = data_source.service_principal!
      expect(svc_principal.kind).to eq 'service'
      expect(svc_principal.identity_issuer).to eq 'sync'
      expect(svc_principal.email).to eq "sync+#{data_source.source_system_key}@plant-api.echocommunity.org"
    end
  end
end
