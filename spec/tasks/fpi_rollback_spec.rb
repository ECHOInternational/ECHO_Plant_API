# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_plant_feed')
require Rails.root.join('lib/fpi_rollback')

RSpec.describe FpiRollback do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:shard) { JSON.parse(Rails.root.join('spec/fixtures/fpi/shard.json').read) }
  let!(:echo_plant) { create(:plant) }

  before do
    create(:category, id: '265c782d-c9e0-4c7a-8ab1-af672572508c')
    Family.importing { create(:family, id: 'a30dbd67-7b44-4acd-b649-f85f89de486c', name: 'Malvaceae') }
  end

  def import(run_id)
    with_versioning do
      feed = FpiPlantFeed.new(data_source: data_source, run_id: run_id)
      feed.run(feed.build(shard))
    end
  end

  it 'plans the removal of one run and applies it across every table, leaving other plants alone' do
    import('run-1')
    fpi_plants = Plant.where(data_source_id: data_source.id)
    expect(fpi_plants.count).to eq(2)
    created_versions = PaperTrail::Version.where(item_type: 'Plant', event: 'create').where("metadata->>'sync_run_id' = 'run-1'")
    expect(created_versions.count).to eq(2)
    conflict = create(:sync_conflict, syncable: fpi_plants.first, data_source: data_source, conflict_type: 'content', status: 'open',
                                      base_payload: {}, local_payload: {}, incoming_payload: {}, sync_run_id: 'run-1')

    plan = described_class.new(data_source: data_source, run_id: 'run-1').run
    expect(plan.plants).to eq(2)
    expect(plan.sync_conflicts).to eq(1)
    expect(plan.joins['common_names']).to eq(4)
    expect(plan.joins['categories_plants']).to eq(1)
    expect(plan.versions).to be >= 2
    expect(Plant.where(data_source_id: data_source.id).count).to eq(2)

    applied = described_class.new(data_source: data_source, run_id: 'run-1', apply: true).run
    expect(applied.plants).to eq(2)
    expect(Plant.where(data_source_id: data_source.id).count).to eq(0)
    expect(CommonName.count).to eq(0)
    expect(CategoriesPlant.count).to eq(0)
    expect(SyncConflict.where(id: conflict.id)).not_to exist
    expect(PaperTrail::Version.where("metadata->>'sync_run_id' = 'run-1'")).not_to exist
    expect(Plant.exists?(echo_plant.id)).to be(true)
  end

  it 'removes only the named run when several ran' do
    import('run-1')
    later = shard.merge('plants' => { 'NEW-1' => shard['plants'].values.first.merge('scientific_name' => 'Later plant', 'common_name_set' => [], 'category_set' => []) })
    with_versioning do
      feed = FpiPlantFeed.new(data_source: data_source, run_id: 'run-2')
      feed.run(feed.build(later))
    end
    expect(Plant.where(data_source_id: data_source.id).count).to eq(3)
    described_class.new(data_source: data_source, run_id: 'run-2', apply: true).run
    expect(Plant.where(data_source_id: data_source.id).pluck(:source_record_id)).not_to include('NEW-1')
    expect(Plant.where(data_source_id: data_source.id).count).to eq(2)
  end

  it 'removes every FPI plant when no run id is given' do
    import('run-1')
    described_class.new(data_source: data_source, apply: true).run
    expect(Plant.where(data_source_id: data_source.id).count).to eq(0)
    expect(Plant.exists?(echo_plant.id)).to be(true)
  end
end
