# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_rebaseline')

RSpec.describe FpiRebaseline do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:old_keys) { FpiDataSource::PLANT_ATTRIBUTES - %w[notes] }

  def fpi_plant(src_id, snapshot_overrides = {}, **local)
    snapshot = old_keys.index_with { |k| FpiDataSource.empty_value(k) }.merge(snapshot_overrides)
    create(:plant, data_source_id: data_source.id, source_record_id: src_id, source_snapshot: snapshot,
                   source_digest: SourceSynchronizer.canonical_digest(snapshot), sync_state: 'synced',
                   owner_organization_id: org.id, source_organization_id: org.id, **local)
  end

  it 'reports the key delta and changes nothing on a dry run' do
    fpi_plant('p1')
    result = described_class.new(data_source: data_source).run
    expect(result.added).to eq(['notes'])
    expect(result.removed).to eq([])
    expect(result.changed).to eq(1)
    expect(result.applied).to be(false)
    expect(Plant.find_by(source_record_id: 'p1').source_snapshot).not_to have_key('notes')
  end

  it 'adds the empty value for a new key, never the local value, and leaves existing keys alone' do
    plant = fpi_plant('p1', { 'description' => 'Upstream text' }, description: 'Curator text')
    Mobility.with_locale(:en) { plant.update!(notes: 'Curator notes') }
    result = described_class.new(data_source: data_source, apply: true).run
    expect(result.changed).to eq(1)
    plant.reload
    expect(plant.source_snapshot['notes']).to eq('')
    expect(plant.source_snapshot['description']).to eq('Upstream text')
    expect(plant.source_digest).to eq(SourceSynchronizer.canonical_digest(plant.source_snapshot))
    expect(ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{result.backup_table}").to_i).to eq(1)
  end

  it 'lets the next run conflict on a curator value in the new key rather than overwrite it' do
    plant = fpi_plant('p1')
    Mobility.with_locale(:en) { plant.update!(notes: 'Curator notes') }
    described_class.new(data_source: data_source, apply: true).run
    row = { source_record_id: 'p1', deleted: false, source_updated_at: 1.hour.ago,
            attributes: FpiDataSource::PLANT_ATTRIBUTES.index_with { |k| FpiDataSource.empty_value(k) }.merge('notes' => 'FPI notes') }
    report = Mobility.with_locale(:en) do
      SourceSynchronizer.new(data_source: data_source, model: Plant, source_attributes: FpiDataSource::PLANT_ATTRIBUTES, run_id: 'r').apply([row])
    end
    expect(report.conflicts_created).to eq(1)
    expect(Mobility.with_locale(:en) { plant.reload.notes }).to eq('Curator notes')
  end

  it 'keeps a locally modified record locally modified' do
    plant = fpi_plant('p1', {}, scientific_name: 'Curator name')
    plant.update_columns(sync_state: 'locally_modified')
    described_class.new(data_source: data_source, apply: true).run
    expect(plant.reload.sync_state).to eq('locally_modified')
    expect(plant.source_snapshot['scientific_name']).to eq('') # the base was never re-read from local
  end

  it 'refuses to run while a conflict is open' do
    plant = fpi_plant('p1')
    create(:sync_conflict, syncable: plant, data_source: data_source, conflict_type: 'content', status: 'open',
                           base_payload: {}, local_payload: {}, incoming_payload: {})
    expect { described_class.new(data_source: data_source, apply: true).run }.to raise_error(FpiRebaseline::Refused, /1 open conflict/)
  end
end
