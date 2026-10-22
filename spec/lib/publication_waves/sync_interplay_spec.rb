# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_data_source')
require Rails.root.join('lib/fpi_plant_feed')

# A wave makes FPI plants public; the FPI sync must never undo or extend that
# (visibility, access_level and publication_state are on the synchronizer's
# DENY_LIST, and creates are private). These examples run the real feed over
# published plants.
RSpec.describe 'publication waves and the FPI sync' do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:shard) { JSON.parse(Rails.root.join('spec/fixtures/fpi/shard.json').read) }
  let(:deletions) { JSON.parse(Rails.root.join('spec/fixtures/fpi/deletions.json').read) }
  let(:feed) { FpiPlantFeed.new(data_source: data_source, run_id: 'interplay') }
  let(:fpi_plants) { Plant.unscoped.where(data_source_id: data_source.id) }

  before do
    create(:category, id: '265c782d-c9e0-4c7a-8ab1-af672572508c')
    Family.importing { create(:family, id: 'a30dbd67-7b44-4acd-b649-f85f89de486c', name: 'Malvaceae') }
    feed.run(feed.build(shard))
    selection = PublicationWaves::Selector.new(data_source: data_source, selector: 'remaining').select
    PublicationWaves::Publisher.new(data_source: data_source, key: 'fpi-w1', selector: 'remaining', apply: true,
                                    expected_digest: selection.digest).run
  end

  def access_levels
    fpi_plants.order(:source_record_id).pluck(:visibility, :access_level, :publication_state)
  end

  it 'publishes the synced plants' do
    expect(access_levels).to eq([%w[public public published]] * 2)
  end

  it 'keeps them public through an unchanged pass' do
    feed.run(feed.build(shard))
    expect(access_levels).to eq([%w[public public published]] * 2)
  end

  it 'keeps them public when upstream edits a record' do
    edited = shard.deep_dup
    row = edited['plants'].values.first
    row['description'] = "#{row['description']} Edited upstream."
    row['source_updated_at'] = '2026-10-01T00:00:00Z'
    report = feed.run(feed.build(edited)).report
    expect(report.applied).to eq(1)
    expect(access_levels).to eq([%w[public public published]] * 2)
  end

  it 'keeps a plant public when upstream deletes it (a conflict is raised instead)' do
    plant = fpi_plants.order(:source_record_id).first
    gone = deletions.merge('deleted' => { plant.source_record_id => { 'source_updated_at' => '2026-10-01T00:00:00Z' } })
    report = feed.run(feed.build_deletions(gone)).report
    expect(report.source_deletion_conflicts).to eq(1)
    expect(plant.reload).to have_attributes(visibility: 'public', deleted_at: nil)
  end

  it 'creates a new upstream record private, outside the wave' do
    added = shard.merge('plants' => { 'NEW-1' => shard['plants'].values.first.merge(
      'scientific_name' => 'Later plant', 'common_name_set' => [], 'category_set' => []
    ) })
    feed.run(feed.build(added))
    expect(fpi_plants.find_by(source_record_id: 'NEW-1').visibility).to eq('private')
    expect(access_levels.count(%w[public public published])).to eq(2)
  end
end
