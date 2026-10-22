# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_image_importer')

RSpec.describe FpiImageImporter do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:s3) { Aws::S3::Client.new(stub_responses: true, region: 'us-east-1') }
  let!(:plant) { create(:plant, data_source_id: data_source.id, source_record_id: 'PLANT-A', owner_organization_id: org.id, source_organization_id: org.id) }
  let!(:other_plant) { create(:plant, data_source_id: data_source.id, source_record_id: 'PLANT-B', owner_organization_id: org.id, source_organization_id: org.id) }
  let(:sha) { 'a' * 64 }

  before { s3.stub_responses(:head_object, { content_length: 100 }) }

  def entry(kind: 'photo', rowid: 7, plant_id: 'PLANT-A', sha256: sha, name: 'Moringa oleifera (photo 1)')
    file = "#{rowid}-#{sha256[0, 12]}.jpg"
    { 'kind' => kind, 'rowid' => rowid, 'plant_id' => plant_id, 'key' => Mutations::CreateSourceUpload.image_key('fpi', kind, file),
      'content_type' => 'image/jpeg', 'sha256' => sha256, 'bytes' => 100, 'name' => name }
  end

  def importer(apply: true, run_id: 'run-images-1')
    described_class.new(data_source: data_source, run_id: run_id, apply: apply, bucket: 'images-test', s3_client: s3)
  end

  def import(*entries, **)
    importer(**).run('images' => entries)
  end

  it 'creates private images under the plant with provenance, a deterministic id and the attribution', versioning: true do
    totals = import(entry)
    expect(totals.created).to eq 1
    image = Image.find(described_class.image_id('photo', 7))
    expect(image).to have_attributes(imageable_id: plant.id, s3_bucket: 'images-test', s3_key: 'test/fpi/photos/7-aaaaaaaaaaaa.jpg',
                                     data_source_id: data_source.id, source_record_id: 'photos:7', source_digest: sha,
                                     attribution: described_class::ATTRIBUTION, created_by: data_source.service_principal!.email)
    expect(image.visibility_private?).to be true
    expect(Mobility.with_locale(:en) { image.name }).to eq 'Moringa oleifera (photo 1)'
    expect(PaperTrail::Version.where(item_type: 'Image', item_id: image.id).last.whodunnit).to eq data_source.service_principal!.id
  end

  it 'tags drawings with the Drawing attribute, creating it when absent' do
    import(entry(kind: 'drawing', rowid: 3, name: 'Moringa oleifera (drawing 1)'))
    image = Image.find(described_class.image_id('drawing', 3))
    expect(image.image_attributes.map { |a| Mobility.with_locale(:en) { a.name } }).to eq ['Drawing']
  end

  it 'is idempotent: a second run over the same manifest changes nothing' do
    import(entry)
    expect { @totals = import(entry, run_id: 'run-images-2') }.not_to change(Image, :count)
    expect(@totals.unchanged).to eq 1
    expect(@totals.created).to eq 0
  end

  it 'replaces an image whose bytes changed, keeping the id and a curator-edited name' do
    import(entry)
    image = Image.find(described_class.image_id('photo', 7))
    Mobility.with_locale(:en) { image.update!(name: 'Curated name') }
    totals = import(entry(sha256: 'b' * 64))
    expect(totals.replaced).to eq 1
    replaced = Image.find(described_class.image_id('photo', 7))
    expect(replaced.s3_key).to eq 'test/fpi/photos/7-bbbbbbbbbbbb.jpg'
    expect(replaced.source_digest).to eq 'b' * 64
    expect(Mobility.with_locale(:en) { replaced.name }).to eq 'Curated name'
  end

  it 're-parents an image whose plant changed upstream' do
    import(entry)
    totals = import(entry(plant_id: 'PLANT-B'))
    expect(totals.reparented).to eq 1
    expect(Image.find(described_class.image_id('photo', 7)).imageable_id).to eq other_plant.id
  end

  it 're-adds a Drawing tag a curator removed' do
    import(entry(kind: 'drawing', rowid: 3))
    ImageAttributesImage.where(image_id: described_class.image_id('drawing', 3)).delete_all
    totals = import(entry(kind: 'drawing', rowid: 3))
    expect(totals.retagged).to eq 1
    expect(Image.find(described_class.image_id('drawing', 3)).image_attributes.count).to eq 1
  end

  it 'writes nothing for a missing plant or an object that was never uploaded' do
    s3.stub_responses(:head_object, 'NotFound')
    totals = import(entry(plant_id: 'NO-SUCH-PLANT'), entry(rowid: 8))
    expect(totals.missing_plant).to eq 1
    expect(totals.not_uploaded).to eq 1
    expect(Image.count).to eq 0
  end

  it 'counts FPI images absent from the manifest and never deletes them' do
    import(entry, entry(rowid: 8))
    totals = import(entry)
    expect(totals.absent_from_manifest).to eq 1
    expect(Image.where(data_source_id: data_source.id).count).to eq 2
  end

  it 'classifies without writing on a dry run' do
    totals = import(entry, apply: false)
    expect(totals.created).to eq 1
    expect(Image.count).to eq 0
  end

  it 'refuses a manifest whose key is not the one createSourceUpload issues' do
    bad = entry.merge('key' => 'fpi/photos/7-aaaaaaaaaaaa.jpg')
    expect { import(bad) }.to raise_error(described_class::InvalidManifest, /createSourceUpload/)
    expect { importer.run('images' => [entry.merge('sha256' => 'short')]) }.to raise_error(described_class::InvalidManifest, /64 hex/)
    expect { importer.run({}) }.to raise_error(described_class::InvalidManifest, /no images/)
  end
  describe 'visibility and display order (FPI plan API-6)' do
    def image_for(kind, rowid)
      Image.find(described_class.image_id(kind, rowid))
    end

    def make_public(record)
      record.update!(visibility: :public)
      record.reload
    end

    it 'creates images on an already-public plant as public (N-3)' do
      make_public(plant)
      import(entry)
      expect(image_for('photo', 7).visibility_public?).to be true
    end

    it 'creates images on a non-public plant as private' do
      import(entry)
      expect(image_for('photo', 7).visibility_private?).to be true
    end

    it 'imports the manifest in plant, photo-before-drawing, rowid order so positions follow the source' do
      import(entry(kind: 'drawing', rowid: 2), entry(rowid: 10), entry(plant_id: 'PLANT-B', rowid: 1), entry(rowid: 9))
      expect(Image.where(imageable: plant).order(:position).pluck(:source_record_id))
        .to eq %w[photos:9 photos:10 drawings:2]
      expect(image_for('photo', 1).position).to eq 1
    end

    it 'carries visibility and position across a replace on the same plant' do
      import(entry(rowid: 6), entry)
      image = image_for('photo', 7)
      image.update!(visibility: :public)
      image.update_columns(position: 1)
      image_for('photo', 6).update_columns(position: 2)

      import(entry(sha256: 'b' * 64))

      replaced = image_for('photo', 7)
      expect(replaced.s3_key).to end_with '7-bbbbbbbbbbbb.jpg'
      expect(replaced.visibility_public?).to be true
      expect(replaced.position).to eq 1
    end

    it 'takes visibility from the new plant and goes last when a replaced image also moved plant' do
      make_public(other_plant)
      import(entry(plant_id: 'PLANT-B', rowid: 3), entry)

      import(entry(plant_id: 'PLANT-B', sha256: 'b' * 64))

      moved = image_for('photo', 7)
      expect(moved.imageable_id).to eq other_plant.id
      expect(moved.visibility_public?).to be true
      expect(moved.position).to eq 2
    end

    it 'makes a re-parented image private when it moves from a public plant to a private one' do
      make_public(plant)
      import(entry)
      expect(image_for('photo', 7).visibility_public?).to be true

      totals = import(entry(plant_id: 'PLANT-B'))

      expect(totals.reparented).to eq 1
      expect(image_for('photo', 7)).to have_attributes(imageable_id: other_plant.id, visibility: 'private')
    end

    it 'makes a re-parented image public when it moves from a private plant to a public one' do
      make_public(other_plant)
      import(entry(plant_id: 'PLANT-B', rowid: 3), entry)
      expect(image_for('photo', 7).visibility_private?).to be true

      import(entry(plant_id: 'PLANT-B', rowid: 3), entry(plant_id: 'PLANT-B'))

      moved = image_for('photo', 7)
      expect(moved).to have_attributes(imageable_id: other_plant.id, visibility: 'public')
      expect(moved.position).to eq 2
    end

    it 'leaves visibility alone on an unchanged image' do
      make_public(plant)
      import(entry)
      image_for('photo', 7).update!(visibility: :private)
      import(entry)
      expect(image_for('photo', 7).visibility_private?).to be true
    end
  end
end
