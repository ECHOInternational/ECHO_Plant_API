# frozen_string_literal: true

require 'rails_helper'

# Relation sets through the engine (schema-delta item 7): a set is a managed
# attribute like any column, so the three-way merge creates, applies, keeps
# local edits, raises conflicts, and converges on it with no engine change.
RSpec.describe SourceSynchronizer, 'with relation sets', type: :service do
  let(:attrs)       { %w[scientific_name common_name_set category_set] }
  let(:org)         { create(:organization, :real) }
  let(:data_source) { create(:data_source, organization: org) }
  let(:leafy)       { create(:category) }
  let(:fruit)       { create(:category) }

  def sync
    SourceSynchronizer.new(data_source: data_source, model: Plant, source_attributes: attrs, run_id: 'run-1')
  end

  def row(src_id, names:, categories:, name: 'Abelmoschus esculentus')
    {
      source_record_id: src_id, deleted: false, source_updated_at: 1.day.ago,
      attributes: {
        'scientific_name' => name,
        'common_name_set' => RelationSets::CommonNames.dump(RelationSets::CommonNames.parse(names)),
        'category_set' => RelationSets::Categories.dump(RelationSets::Categories.parse(categories))
      }
    }
  end

  it 'creates a plant with its join rows in one save' do
    report = sync.apply([row('p1', names: [['EN', 'Okra', true], ['UND', 'Bhindi', false]], categories: [leafy.id.to_s])])
    expect(report.created).to eq(1)
    plant = Plant.find_by(source_record_id: 'p1')
    expect(plant.common_name_set).to eq('[["EN","Okra",true],["UND","Bhindi",false]]')
    expect(plant.category_set).to eq(JSON.generate([leafy.id.to_s]))
    expect(plant.source_snapshot).to include('common_name_set' => plant.common_name_set, 'category_set' => plant.category_set)
  end

  it 'scores an unchanged second pass as synced with no writes' do
    sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [leafy.id.to_s])])
    expect do
      report = sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [leafy.id.to_s])])
      expect(report.synced).to eq(1)
      expect(report.applied).to eq(0)
    end.not_to change { PaperTrail::Version.count }
  end

  it 'applies an upstream change to a set when the local side is untouched' do
    sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [leafy.id.to_s])])
    report = sync.apply([row('p1', names: [['EN', 'Okra', true], ['EN', 'Gumbo', false]], categories: [fruit.id.to_s])])
    expect(report.applied).to eq(1)
    plant = Plant.find_by(source_record_id: 'p1')
    expect(plant.common_name_set).to eq('[["EN","Gumbo",false],["EN","Okra",true]]')
    expect(plant.category_set).to eq(JSON.generate([fruit.id.to_s]))
    expect(CategoriesPlant.where(plant: plant, category: leafy)).not_to exist
  end

  it 'keeps a curator edit to a set as locally_modified when upstream is unchanged' do
    sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [])])
    plant = Plant.find_by(source_record_id: 'p1')
    CategoriesPlant.create!(plant: plant, category: leafy) # a curator adds a category directly
    report = sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [])])
    expect(report.locally_modified).to eq(1)
    expect(plant.reload.category_set).to eq(JSON.generate([leafy.id.to_s]))
  end

  it 'raises a conflict when both sides changed the set differently' do
    sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [])])
    plant = Plant.find_by(source_record_id: 'p1')
    CategoriesPlant.create!(plant: plant, category: leafy)
    report = sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [fruit.id.to_s])])
    expect(report.conflicts_created).to eq(1)
    conflict = SyncConflict.find_by(syncable: plant)
    expect(conflict.local_payload['category_set']).to eq(JSON.generate([leafy.id.to_s]))
    expect(conflict.incoming_payload['category_set']).to eq(JSON.generate([fruit.id.to_s]))
    expect(plant.reload.category_set).to eq(JSON.generate([leafy.id.to_s])) # nothing applied
  end

  it 'converges when both sides made the same change' do
    sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [])])
    plant = Plant.find_by(source_record_id: 'p1')
    CategoriesPlant.create!(plant: plant, category: leafy)
    report = sync.apply([row('p1', names: [['EN', 'Okra', true]], categories: [leafy.id.to_s])])
    expect(report.synced).to eq(1)
    expect(report.conflicts_created).to eq(0)
    expect(plant.reload.source_snapshot['category_set']).to eq(JSON.generate([leafy.id.to_s]))
  end

  it 'counts a set naming an unknown category as invalid and writes nothing' do
    report = sync.apply([row('p1', names: [], categories: ['00000000-0000-4000-8000-000000000000'])])
    expect(report.invalid).to eq(1)
    expect(report.invalid_details.first[:source_record_id] || report.invalid_details.first['source_record_id']).to eq('p1')
    expect(Plant.find_by(source_record_id: 'p1')).to be_nil
  end
end
