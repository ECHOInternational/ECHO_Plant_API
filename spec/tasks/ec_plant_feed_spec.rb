# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_data_source')
require Rails.root.join('lib/ec_plant_feed')

RSpec.describe EcPlantFeed do
  let(:org) { create(:organization, :real) }
  let(:data_source) { EcDataSource.find_or_create!(organization: org) }
  let(:feed) { described_class.new(data_source: data_source, run_id: 'test-run') }

  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  # A realistically linked record, seeded the way EcRecordLinker seeds it in
  # production: the base IS the plant's current local state. Seeding a base that
  # disagrees with local means both sides have already moved, which is a
  # conflict by definition — a trap worth avoiding in specs as well as in
  # production, and one the plant factory sets by populating `description`.
  def link!(**overrides)
    Mobility.with_locale(:en) { plant.update!(overrides) } if overrides.any?
    base = SourceSynchronizer.local_attrs(plant.reload, EcDataSource::PLANT_ATTRIBUTES)
    plant.update_columns(data_source_id: data_source.id, source_record_id: plant.id,
                         source_snapshot: base,
                         source_digest: SourceSynchronizer.canonical_digest(base))
    base
  end

  # An upstream row: the linked base with some fields changed.
  def upstream(base, **overrides)
    base.merge(overrides.transform_keys(&:to_s))
  end

  describe 'row shape' do
    # A key missing from a row is not "unchanged" - it changes the digest and
    # reads as an edit, so absent text must be sent as ''.
    it 'fills every governed attribute, using empty string for absent text' do
      row = feed.build({ 'uuid-1' => { 'uses' => 'Fodder' } }).first

      expect(row[:attributes].keys).to match_array EcDataSource::PLANT_ATTRIBUTES
      expect(row[:attributes]['uses']).to eq 'Fodder'
      expect(row[:attributes]['cultivation']).to eq ''
    end

    it 'rejects a row carrying a key this data source does not govern' do
      expect { feed.build({ 'uuid-1' => { 'visibility' => 'public' } }) }
        .to raise_error(EcPlantFeed::IncompleteRow, /does not govern: visibility/)
    end

    it 'treats source_updated_at as row metadata, not an attribute' do
      stamp = 3.days.ago
      row = feed.build({ 'uuid-1' => { 'uses' => 'x', 'source_updated_at' => stamp } }).first

      expect(row[:source_updated_at]).to eq stamp
      expect(row[:attributes]).not_to have_key 'source_updated_at'
    end

    # Deletions are never inferred from absence: a half-finished export must not
    # read as upstream deletions.
    it 'never marks a row deleted' do
      expect(feed.build({ 'uuid-1' => { 'uses' => 'x' } }).first[:deleted]).to be false
    end
  end

  describe 'running against the synchronizer' do
    it 'applies an upstream change when nobody edited the API copy' do
      base = link!(uses: 'Original')
      result = feed.run({ plant.id => upstream(base, uses: 'Updated upstream') })

      expect(result.report.applied).to eq 1
      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'Updated upstream'
    end

    it 'scores an unchanged record as synced rather than modified' do
      base = link!(uses: 'Same')

      report = feed.run({ plant.id => base }).report
      expect(report.synced).to eq 1
      expect(report.locally_modified).to eq 0
    end

    # The point of seeding the 2020 export as the base: only records edited in
    # plant-admin AND changed upstream become conflicts.
    it 'raises a conflict only when both sides moved from the base' do
      base = link!(uses: 'The 2020 text')
      Mobility.with_locale(:en) { plant.update!(uses: 'Curator edit') }

      result = feed.run({ plant.id => upstream(base, uses: 'Upstream edit') })

      expect(result.report.conflicts_created).to eq 1
      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'Curator edit'
    end

    it 'keeps a local edit when upstream still matches the base' do
      base = link!(uses: 'The 2020 text')
      Mobility.with_locale(:en) { plant.update!(uses: 'Curator edit') }

      result = feed.run({ plant.id => base })

      expect(result.report.locally_modified).to eq 1
      expect(result.report.conflicts_created).to eq 0
    end

    it 'syncs in English regardless of the ambient locale' do
      base = link!(uses: 'Original')
      Mobility.with_locale(:es) { feed.run({ plant.id => upstream(base, uses: 'Updated') }) }

      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'Updated'
    end

    it 'builds rows without touching anything on a dry run' do
      base = link!(uses: 'Original')
      result = feed.run({ plant.id => upstream(base, uses: 'Updated') }, apply: false)

      expect(result.rows.size).to eq 1
      expect(result.report).to be_nil
      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'Original'
    end
  end
end
