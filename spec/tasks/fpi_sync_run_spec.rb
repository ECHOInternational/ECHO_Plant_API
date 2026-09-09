# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_sync_run')

RSpec.describe FpiSyncRun do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:payload_dir) { Dir.mktmpdir('fpi-payload') }
  let(:out_dir) { Dir.mktmpdir('fpi-out') }
  let(:shard) { Rails.root.join('spec/fixtures/fpi/shard.json').read }
  let(:deletions) { Rails.root.join('spec/fixtures/fpi/deletions.json').read }

  before do
    FpiSyncRun::PINNED_CATEGORY_IDS.each { |id| create(:category, id: id) }
    Family.importing { create(:family, id: 'a30dbd67-7b44-4acd-b649-f85f89de486c', name: 'Malvaceae') }
    write_payload(shard, deletions)
  end

  after do
    FileUtils.rm_rf([payload_dir, out_dir])
  end

  def write_payload(shard_text, deletions_text)
    File.write(File.join(payload_dir, 'shard-000.json'), shard_text)
    File.write(File.join(payload_dir, 'deletions.json'), deletions_text)
    File.write(File.join(payload_dir, 'payload-manifest.json'), JSON.generate(
                                                                  snapshot_id: '3c8a266f0bf557e1', environment: 'test', attributes_version: 1,
                                                                  shards: [{ file: 'shard-000.json', sha256: Digest::SHA256.hexdigest(shard_text) }],
                                                                  deletions: { file: 'deletions.json', sha256: Digest::SHA256.hexdigest(deletions_text) }
                                                                ))
  end

  def run(apply: false, run_id: 'run-1')
    described_class.new(data_source: data_source, payload_dir: payload_dir, run_id: run_id, apply: apply, out_dir: out_dir)
  end

  describe 'preflight' do
    it 'passes on a complete payload and reports what it checked' do
      facts = run.preflight!
      expect(facts[:pending_migrations]).to eq([])
      expect(facts[:attributes_version]).to eq(1)
      expect(facts[:shards].size).to eq(1)
      expect(facts[:deletions][:file]).to eq('deletions.json')
      expect(facts[:principal]).to eq('sync+fpi@plant-api.echocommunity.org')
    end

    it 'refuses a shard whose digest differs from the manifest' do
      File.write(File.join(payload_dir, 'shard-000.json'), shard.sub('Medik.', 'L.'))
      expect { run.preflight! }.to raise_error(FpiSyncRun::PreflightFailed, /shard-000.json: sha256/)
    end

    it 'refuses when a pinned category is missing' do
      Category.unscoped.find(FpiSyncRun::PINNED_CATEGORY_IDS.last).destroy!
      expect { run.preflight! }.to raise_error(FpiSyncRun::PreflightFailed, /pinned categories missing/)
    end

    it 'refuses another attributes version' do
      manifest = JSON.parse(File.read(File.join(payload_dir, 'payload-manifest.json')))
      File.write(File.join(payload_dir, 'payload-manifest.json'), JSON.generate(manifest.merge('attributes_version' => 2)))
      expect { run.preflight! }.to raise_error(FpiSyncRun::PreflightFailed, /attributes_version 2/)
    end
  end

  describe 'running' do
    it 'builds every row and sends nothing on a dry run' do
      totals = run.run
      expect(totals.shards).to eq(1)
      expect(totals.rows).to eq(3) # two plants + one deletion
      expect(totals.created).to eq(0)
      expect(Plant.where(data_source_id: data_source.id).count).to eq(0)
      expect(File).not_to exist(File.join(out_dir, 'summary.json'))
    end

    it 'applies the shards and the deletions and writes the outcome files' do
      totals = run(apply: true).run
      expect(totals.created).to eq(2)
      expect(totals.unknown_deleted).to eq(1)
      expect(described_class.failed?(totals)).to be(false)
      outcomes = File.readlines(File.join(out_dir, 'outcomes.jsonl')).map { |l| JSON.parse(l) }
      expect(outcomes.size).to eq(2)
      expect(outcomes).to all(include('sync_state' => 'synced', 'created' => true, 'conflict_id' => nil))
      summary = JSON.parse(File.read(File.join(out_dir, 'summary.json')))
      expect(summary['run_id']).to eq('run-1')
      expect(summary['totals']).to include('created' => 2, 'rows' => 3)
    end

    it 'scores a second run of the same payload as synced and records nothing new' do
      run(apply: true, run_id: 'run-1').run
      totals = run(apply: true, run_id: 'run-2').run
      expect(totals.synced).to eq(2)
      expect(totals.applied).to eq(0)
      expect(totals.created).to eq(0)
    end

    it 'predicts the run on a dry run and refuses an applied run over the conflict cap' do
      run(apply: true, run_id: 'run-1').run
      Plant.find_by(source_record_id: '495A01C7-C950-4432-B603-EFA260631E03').update!(scientific_name: 'Curator edit')
      changed = shard.sub('"scientific_name": "Abelmoschus moschatus"', '"scientific_name": "Upstream edit"')
      write_payload(changed, deletions)

      dry = run.run
      expect(dry.prediction.to_h).to include(conflict: 1, synced: 1, unknown_deleted: 1, rows: 3)

      capped = described_class.new(data_source: data_source, payload_dir: payload_dir, run_id: 'run-2', apply: true, out_dir: out_dir, conflict_cap: 0)
      expect { capped.run }.to raise_error(FpiSyncRun::CapExceeded, /1 conflicts predicted, over the cap of 0/)
      expect(SyncConflict.count).to eq(0)
      expect(Plant.find_by(source_record_id: '495A01C7-C950-4432-B603-EFA260631E03').scientific_name).to eq('Curator edit')
    end

    it 'counts an invalid row as a failed run' do
      bad = shard.sub('"safety_level": "poisonous"', '"safety_level": "lethal"')
      write_payload(bad, deletions)
      totals = run(apply: true).run
      expect(totals.invalid).to eq(1)
      expect(described_class.failed?(totals)).to be(true)
      expect(totals.invalid_details.first.to_s).to match(/54C3709C/)
    end
  end
end
