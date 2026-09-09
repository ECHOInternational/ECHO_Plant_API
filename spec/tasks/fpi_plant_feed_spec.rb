# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_data_source')
require Rails.root.join('lib/fpi_plant_feed')

# The FPI feed contract (fpi-connector schema-delta item 1) and the digest
# symmetry that keeps a recurring source quiet: the fixture shard is the
# connector's own output shape, and a second pass over it must score every
# row `synced`.
RSpec.describe FpiPlantFeed do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:feed) { described_class.new(data_source: data_source, run_id: 'fpi-test-run') }
  let(:shard) { JSON.parse(Rails.root.join('spec/fixtures/fpi/shard.json').read) }
  let(:deletions) { JSON.parse(Rails.root.join('spec/fixtures/fpi/deletions.json').read) }
  let(:first_row) { shard['plants'].values.first }

  before do
    create(:category, id: '265c782d-c9e0-4c7a-8ab1-af672572508c')
    Family.importing { create(:family, id: 'a30dbd67-7b44-4acd-b649-f85f89de486c', name: 'Malvaceae') }
  end

  describe 'the managed set' do
    it 'has a reader on Plant for every managed attribute' do
      expect { described_class.ensure_readable! }.not_to raise_error
    end

    it 'names an empty value for every key and never a deny-listed key' do
      FpiDataSource::PLANT_ATTRIBUTES.each { |a| expect(FpiDataSource.empty_value(a)).to be_a(String) }
      expect(FpiDataSource::PLANT_ATTRIBUTES & SourceSynchronizer::DENY_LIST).to be_empty
    end
  end

  describe 'row shape' do
    it 'builds one row per plant with every value a String and the sets canonicalised' do
      rows = feed.build(shard)
      expect(rows.size).to eq(2)
      row = rows.first
      expect(row[:source_record_id]).to eq('495A01C7-C950-4432-B603-EFA260631E03')
      expect(row[:deleted]).to be(false)
      expect(row[:attributes].keys).to match_array(FpiDataSource::PLANT_ATTRIBUTES)
      expect(row[:attributes].values).to all(be_a(String))
      expect(row[:attributes]['common_name_set']).to eq('[["EN","Bush carrot",false],["EN","Musk mallow",true],["UND","Abelmosco",false],["UND","Adusa",false]]')
      expect(row[:attributes]['category_set']).to eq('["265c782d-c9e0-4c7a-8ab1-af672572508c"]')
      expect(row[:attributes]['edibility_uncertain']).to eq('false')
      expect(row[:source_updated_at]).to eq('2026-09-08T23:25:05Z')
    end

    it 'refuses a row missing a managed key' do
      first_row.delete('habitat')
      expect { feed.build(shard) }.to raise_error(FpiPlantFeed::IncompleteRow, /missing managed keys: habitat/)
    end

    it 'refuses a row carrying a key this data source does not govern' do
      first_row['visibility'] = 'public'
      expect { feed.build(shard) }.to raise_error(FpiPlantFeed::IncompleteRow, /does not govern: visibility/)
    end

    it 'refuses a family_id that is not a lower-case UUID' do
      first_row['family_id'] = 'A30DBD67-7B44-4ACD-B649-F85F89DE486C'
      expect { feed.build(shard) }.to raise_error(FpiPlantFeed::IncompleteRow, /family_id is not a lower-case UUID/)
    end

    it 'refuses a malformed relation set with the serializer message' do
      first_row['common_name_set'] = [%w[EN Okra]]
      expect { feed.build(shard) }.to raise_error(FpiPlantFeed::IncompleteRow, /common_name_set: .*\[language, name, primary\]/)
    end

    it 'strips NUL bytes and stringifies scalars' do
      first_row['notes'] = "a\u0000b"
      first_row['edibility_uncertain'] = true
      row = feed.build(shard).first
      expect(row[:attributes]['notes']).to eq('ab')
      expect(row[:attributes]['edibility_uncertain']).to eq('true')
    end

    it 'refuses a payload built for another attributes version' do
      shard['attributes_version'] = 2
      expect { feed.build(shard) }.to raise_error(FpiPlantFeed::VersionMismatch, /expects 1/)
    end

    it 'turns the deletions file into deleted rows with no attributes' do
      rows = feed.build_deletions(deletions)
      expect(rows).to eq([{ source_record_id: '0B7B6B5C-1E7B-4B7E-9B3C-000000000001', deleted: true, attributes: {},
                            source_updated_at: '2026-09-09T01:44:29Z' }])
    end
  end

  describe 'running against the synchronizer' do
    it 'creates every plant on the first pass, with its family, safety, names and categories' do
      report = feed.run(feed.build(shard)).report
      expect(report.created).to eq(2)
      expect(report.invalid).to eq(0)
      expect(report.errored).to eq(0)
      plant = Plant.find_by(data_source_id: data_source.id, source_record_id: '495A01C7-C950-4432-B603-EFA260631E03')
      expect(plant.family_id).to eq('a30dbd67-7b44-4acd-b649-f85f89de486c')
      expect(plant.scientific_name_authority).to eq('Medik.')
      expect(plant.common_names.where(language: 'EN', primary: true).pluck(:name)).to eq(['Musk mallow'])
      expect(plant.categories.pluck(:id)).to eq(['265c782d-c9e0-4c7a-8ab1-af672572508c'])
      expect(Mobility.with_locale(:en) { plant.habitat }).to eq('A tropical plant.')
      poisonous = Plant.find_by(data_source_id: data_source.id, source_record_id: '54C3709C-942C-42E3-BC6E-F117D50516EB')
      expect([poisonous.safety_level, poisonous.safety_warning, poisonous.edibility_uncertain, poisonous.family_id]).to eq(['poisonous', true, true, nil])
      expect(Mobility.with_locale(:en) { poisonous.safety_note }).to eq('Seeds (POISONOUS)')
    end

    it 'scores a second pass over the same shard as synced for every row, applying and versioning nothing' do
      feed.run(feed.build(shard))
      expect do
        report = feed.run(feed.build(shard)).report
        expect(report.synced).to eq(2)
        expect(report.applied).to eq(0)
        expect(report.conflicts_created).to eq(0)
        expect(report.invalid).to eq(0)
      end.not_to change { PaperTrail::Version.count }
    end

    it 'raises a source_deletion conflict for a deleted row and changes nothing' do
      feed.run(feed.build(shard))
      plant = Plant.find_by(source_record_id: '495A01C7-C950-4432-B603-EFA260631E03')
      gone = deletions.merge('deleted' => { plant.source_record_id => { 'source_updated_at' => '2026-09-09T01:44:29Z' } })
      report = feed.run(feed.build_deletions(gone)).report
      expect(report.source_deletion_conflicts).to eq(1)
      expect(plant.reload.deleted_at).to be_nil
      expect(SyncConflict.find_by(syncable: plant).conflict_type).to eq('source_deletion')
    end

    it 'counts a deletion for a plant it never had as unknown_deleted' do
      report = feed.run(feed.build_deletions(deletions)).report
      expect(report.unknown_deleted).to eq(1)
    end
  end
end
