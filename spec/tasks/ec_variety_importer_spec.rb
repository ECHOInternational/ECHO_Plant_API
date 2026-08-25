# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_variety_importer')

RSpec.describe EcVarietyImporter do
  let(:org) { create(:organization, :real) }
  let(:principal) { create(:principal) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end
  let(:uuid) { SecureRandom.uuid }

  def import(varieties, apply: true)
    described_class.new(organization: org, principal: principal,
                        owner_email: 'echo@echonet.org', apply: apply).import(varieties)
  end

  def row(**overrides)
    { 'plant_uuid' => plant.id, 'parent_published' => true,
      'translations' => { 'en' => { 'name' => 'Ruang puang' } } }.merge(overrides)
  end

  it 'creates a variety under the ECHOcommunity uuid' do
    result = import({ uuid => row })

    expect(result.created).to eq 1
    v = Variety.unscoped.find(uuid)
    expect(Mobility.with_locale(:en) { v.name }).to eq 'Ruang puang'
    expect(v.plant_id).to eq plant.id
  end

  it 'publishes it, with the visibility trio consistent' do
    import({ uuid => row })

    v = Variety.unscoped.find(uuid)
    expect(v.visibility).to eq 'public'
    expect(v.access_level).to eq 'public'
    expect(v.deleted_at).to be_nil
  end

  it 'carries description and planting instructions when present' do
    import({ uuid => row('translations' => { 'en' => {
                           'name' => 'NS-1', 'description' => 'A jackfruit selection.',
                           'planting_instructions' => 'Graft in spring.'
                         } }) })

    v = Variety.unscoped.find(uuid)
    Mobility.with_locale(:en) do
      expect(v.description).to eq 'A jackfruit selection.'
      expect(v.planting_instructions).to eq 'Graft in spring.'
    end
  end

  it 'creates every named locale' do
    import({ uuid => row('translations' => { 'en' => { 'name' => 'Sweet' },
                                             'th' => { 'name' => 'หวาน' } }) })

    v = Variety.unscoped.find(uuid)
    expect(Mobility.with_locale(:th) { v.name }).to eq 'หวาน'
  end

  # The direction of richness is reversed for varieties: the API side carries 29
  # translated fields against ECHOcommunity's three, so this must never merge.
  it 'never touches a variety that already exists' do
    existing = create(:variety, plant: plant, owner_organization_id: org.id,
                                source_organization_id: org.id)
    before = Mobility.with_locale(:en) { existing.name }

    result = import({ existing.id => row('translations' => { 'en' => { 'name' => 'Thin name' } }) })

    expect(result.already_present).to eq 1
    expect(result.created).to eq 0
    expect(Mobility.with_locale(:en) { existing.reload.name }).to eq before
  end

  it 'leaves an already-deleted variety alone rather than resurrecting it' do
    existing = create(:variety, plant: plant, owner_organization_id: org.id,
                                source_organization_id: org.id)
    existing.update!(visibility: :deleted)

    result = import({ existing.id => row })

    expect(result.already_present).to eq 1
    expect(existing.reload.visibility).to eq 'deleted'
  end

  it 'skips a variety whose parent plant is not in the API' do
    result = import({ uuid => row('plant_uuid' => SecureRandom.uuid) })

    expect(result.missing_plants).to eq 1
    expect(result.created).to eq 0
    expect(Variety.unscoped.exists?(id: uuid)).to be false
  end

  it 'skips a variety with no name in any locale' do
    result = import({ uuid => row('translations' => { 'en' => { 'description' => 'orphan' } }) })

    expect(result.no_name).to eq 1
    expect(result.created).to eq 0
  end

  it 'records a failure without aborting the batch' do
    other = SecureRandom.uuid
    allow(Variety).to receive(:new).and_call_original
    allow(Variety).to receive(:new).with(hash_including(id: uuid))
                                   .and_raise(ActiveRecord::RecordInvalid.new(Variety.new))

    result = import({ uuid => row, other => row })

    expect(result.failed).to eq 1
    expect(result.created).to eq 1
    expect(Variety.unscoped.exists?(id: other)).to be true
  end

  it 'writes nothing on a dry run' do
    result = import({ uuid => row }, apply: false)

    expect(result.created).to eq 1
    expect(Variety.unscoped.exists?(id: uuid)).to be false
  end
end
