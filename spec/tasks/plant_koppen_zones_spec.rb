# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_koppen_zone_importer')
require Rails.root.join('lib/koppen_zone_seeder')

RSpec.describe EcKoppenZoneImporter do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  before { KoppenZoneSeeder.new(apply: true).seed }

  def import(plants, apply: true)
    described_class.new(apply: apply).import(plants)
  end

  it 'links a plant to the zones it is assigned' do
    result = import({ plant.id => %w[Cfa Aw] })

    expect(result.linked).to eq 2
    expect(plant.reload.koppen_zones.map(&:code)).to contain_exactly('Cfa', 'Aw')
  end

  # ECHOcommunity's zone ids are integers on an un-foreign-keyed table whose
  # rows have been deleted before; the code is the only shared identifier.
  it 'matches the zone code case-insensitively' do
    result = import({ plant.id => ['cfa'] })

    expect(result.linked).to eq 1
    expect(plant.reload.koppen_zones.first.code).to eq 'Cfa'
  end

  it 'does not duplicate a link that already exists' do
    import({ plant.id => ['Cfa'] })
    result = import({ plant.id => ['Cfa'] })

    expect(result.linked).to eq 0
    expect(result.present).to eq 1
    expect(plant.reload.koppen_zones.count).to eq 1
  end

  # koppen_zones is a locked list. A code that is not in it means the seed and
  # the payload disagree, which must surface rather than be papered over.
  it 'reports an unknown zone code and never creates one' do
    result = import({ plant.id => %w[Cfa Zz] })

    expect(result.unknown_zones).to eq ['Zz']
    expect(result.linked).to eq 1
    expect(KoppenZone.count).to eq 45
  end

  it 'skips a plant that is not in this database' do
    result = import({ SecureRandom.uuid => ['Cfa'] })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  # Removing an assignment is an editorial act, not a migration one.
  it 'is additive: a zone the payload omits stays linked' do
    import({ plant.id => %w[Cfa Aw] })
    import({ plant.id => ['Cfa'] })

    expect(plant.reload.koppen_zones.map(&:code)).to contain_exactly('Cfa', 'Aw')
  end

  it 'links to a subgroup, which is where most assignments sit' do
    result = import({ plant.id => ['Cf'] })

    expect(result.linked).to eq 1
    expect(plant.reload.koppen_zones.first.level).to eq 'subgroup'
  end

  it 'writes nothing on a dry run' do
    result = import({ plant.id => ['Cfa'] }, apply: false)

    expect(result.linked).to eq 1
    expect(plant.reload.koppen_zones).to be_empty
  end
end
