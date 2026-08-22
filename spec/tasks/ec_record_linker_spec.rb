# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_data_source')
require Rails.root.join('lib/ec_record_linker')

RSpec.describe EcRecordLinker do
  let(:org) { create(:organization, :real) }
  let(:data_source) { EcDataSource.find_or_create!(organization: org) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  def link(uuids, baseline: {}, apply: true)
    described_class.new(data_source: data_source, source_uuids: uuids.to_set,
                        baseline: baseline, apply: apply).link
  end

  # Without this stamping, SourceSynchronizer matches nothing and takes the
  # create branch for every row — duplicating the entire table.
  it 'stamps the data source and the shared uuid as source_record_id' do
    result = link([plant.id])

    expect(result.linked).to eq 1
    plant.reload
    expect(plant.data_source_id).to eq data_source.id
    expect(plant.source_record_id).to eq plant.id
  end

  it 'seeds the merge base from the 2020 export when it has the plant' do
    baseline = { plant.id => { 'uses' => 'Historic 2020 text' } }
    result = link([plant.id], baseline: baseline)

    expect(result.based_on_seed).to eq 1
    expect(plant.reload.source_snapshot).to eq('uses' => 'Historic 2020 text')
  end

  # Plants this migration imported came from ECHOcommunity and have not
  # diverged, so their base is what they currently hold.
  it 'falls back to current local state when the export has no entry' do
    Mobility.with_locale(:en) { plant.update!(uses: 'Imported text') }
    result = link([plant.id])

    expect(result.based_on_local).to eq 1
    expect(plant.reload.source_snapshot['uses']).to eq 'Imported text'
  end

  it 'records a digest matching the snapshot it wrote' do
    link([plant.id], baseline: { plant.id => { 'uses' => 'x' } })

    plant.reload
    expect(plant.source_digest)
      .to eq SourceSynchronizer.canonical_digest(plant.source_snapshot)
  end

  # Stamping a plant with no upstream original would invite a later feed to
  # read its absence as an upstream deletion.
  it 'leaves a plant ECHOcommunity does not have alone' do
    plant # the linker walks every plant, so it must exist before the run
    result = link([])

    expect(result.not_in_source).to eq 1
    expect(result.linked).to eq 0
    expect(plant.reload.data_source_id).to be_nil
  end

  it 'is idempotent: a linked plant is not relinked or rebased' do
    link([plant.id], baseline: { plant.id => { 'uses' => 'first' } })
    result = link([plant.id], baseline: { plant.id => { 'uses' => 'second' } })

    expect(result.already_linked).to eq 1
    expect(result.linked).to eq 0
    expect(plant.reload.source_snapshot).to eq('uses' => 'first')
  end

  # Provenance bookkeeping, not an editorial change: no validations, no
  # updated_at bump, no version implying a human edited the plant.
  it 'does not touch updated_at or create a version' do
    before_updated = plant.updated_at
    before_versions = PaperTrail::Version.where(item_id: plant.id).count

    link([plant.id])

    expect(plant.reload.updated_at).to eq before_updated
    expect(PaperTrail::Version.where(item_id: plant.id).count).to eq before_versions
  end

  it 'writes nothing on a dry run' do
    result = link([plant.id], apply: false)

    expect(result.linked).to eq 1
    expect(plant.reload.data_source_id).to be_nil
  end

  describe '.baseline_from_seed' do
    it 'flattens the English translations onto the row' do
      file = Rails.root.join('tmp/test_baseline.json')
      File.write(file, JSON.generate([{ 'uuid' => 'u1', 'scientific_name' => 'S',
                                        'translations' => { 'en' => { 'uses' => 'U' } } }]))
      base = described_class.baseline_from_seed(%w[uses scientific_name], file)

      expect(base['u1']).to eq('uses' => 'U', 'scientific_name' => 'S')
    ensure
      FileUtils.rm_f(file)
    end

    it 'reads the real 2020 export, which is the documented merge base' do
      base = described_class.baseline_from_seed(EcDataSource::PLANT_ATTRIBUTES)

      expect(base.size).to eq(322), 'the checksummed baseline holds exactly 322 plants'
      expect(base.values.first.keys).to match_array EcDataSource::PLANT_ATTRIBUTES
    end
  end
end
