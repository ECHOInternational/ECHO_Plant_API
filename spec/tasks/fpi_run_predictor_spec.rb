# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_run_predictor')

RSpec.describe FpiRunPredictor do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:attrs) { %w[scientific_name family_names] }
  let(:predictor) { described_class.new(data_source: data_source, attributes: attrs) }

  def row(src_id, name: 'Moringa oleifera', deleted: false)
    { source_record_id: src_id, deleted: deleted, attributes: { 'scientific_name' => name, 'family_names' => 'Moringaceae' }, source_updated_at: 1.day.ago }
  end

  def plant(src_id, base_name:, local_name: base_name, deleted_at: nil)
    base = { 'scientific_name' => base_name, 'family_names' => 'Moringaceae' }
    create(:plant, data_source_id: data_source.id, source_record_id: src_id, source_snapshot: base, deleted_at: deleted_at,
                   source_digest: SourceSynchronizer.canonical_digest(base), scientific_name: local_name, family_names: 'Moringaceae',
                   owner_organization_id: org.id, source_organization_id: org.id)
  end

  it 'classifies every outcome the engine has, without writing' do
    plant('synced', base_name: 'A')
    plant('applied', base_name: 'A')
    plant('local', base_name: 'A', local_name: 'Curator')
    plant('conflict', base_name: 'A', local_name: 'Curator')
    plant('converge', base_name: 'A', local_name: 'Both')
    plant('gone', base_name: 'A')
    plant('tomb', base_name: 'A', deleted_at: Time.current)
    rows = [row('synced', name: 'A'), row('applied', name: 'B'), row('local', name: 'A'), row('conflict', name: 'B'),
            row('converge', name: 'Both'), row('gone', deleted: true), row('tomb', name: 'A'), row('new', name: 'N'), row('never', deleted: true)]

    prediction = nil
    expect { prediction = predictor.predict(rows) }.not_to change { [Plant.count, SyncConflict.count, PaperTrail::Version.count] }
    expect(prediction.to_h).to eq(
      create: 1, synced: 1, applied: 1, locally_modified: 1, conflict: 1, converge: 1,
      source_deletion: 1, tombstone_kept: 1, unknown_deleted: 1, rows: 9
    )
  end

  it 'treats a record with no base as synced only when local equals incoming' do
    create(:plant, data_source_id: data_source.id, source_record_id: 'nobase', source_snapshot: nil, scientific_name: 'Same',
                   family_names: 'Moringaceae', owner_organization_id: org.id, source_organization_id: org.id)
    expect(predictor.classify(row('nobase', name: 'Same'))).to eq(:synced)
    expect(predictor.classify(row('nobase', name: 'Other'))).to eq(:conflict)
  end

  it 'lets a local tombstone win even when upstream repeats the deletion' do
    plant('tomb-again', base_name: 'A', deleted_at: Time.current)
    expect(predictor.classify(row('tomb-again', deleted: true))).to eq(:tombstone_kept)
    expect(predictor.classify(row('tomb-again', name: 'A'))).to eq(:tombstone_kept)
  end
end
