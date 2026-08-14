# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EcScientificNameSync do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id,
                   scientific_name: 'Cyphomandra betacea')
  end

  def sync(plants, apply: true)
    described_class.new(apply: apply).sync(plants)
  end

  it 'promotes the incoming scientific name' do
    result = sync({ plant.id => 'Solanum betaceum' })

    expect(result.changed).to eq 1
    expect(plant.reload.scientific_name).to eq 'Solanum betaceum'
  end

  it 'leaves a plant alone when the name already matches' do
    result = sync({ plant.id => 'Cyphomandra betacea' })

    expect(result.changed).to eq 0
    expect(result.unchanged).to eq 1
  end

  # The scientific name becomes the plant's title on ECHOcommunity, so writing a
  # blank would leave the page untitled.
  it 'never writes a blank name' do
    result = sync({ plant.id => '' })

    expect(result.blank_skipped).to eq 1
    expect(result.changed).to eq 0
    expect(plant.reload.scientific_name).to eq 'Cyphomandra betacea'
  end

  it 'reports a plant that is not in this database instead of failing' do
    result = sync({ SecureRandom.uuid => 'Solanum betaceum' })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  it 'changes nothing on a dry run but still reports what would change' do
    result = sync({ plant.id => 'Solanum betaceum' }, apply: false)

    expect(result.changed).to eq 1
    expect(result.changes.first).to include 'Solanum betaceum'
    expect(plant.reload.scientific_name).to eq 'Cyphomandra betacea'
  end

  # Only the one column moves; the migration must not disturb ownership,
  # visibility or the translated fields.
  it 'touches nothing but scientific_name' do
    before = plant.attributes.except('scientific_name', 'updated_at')
    sync({ plant.id => 'Solanum betaceum' })

    expect(plant.reload.attributes.except('scientific_name', 'updated_at'))
      .to eq before
  end

  it 'finds a draft or deleted plant, which the default scope would hide' do
    plant.update!(visibility: :deleted)
    result = sync({ plant.id => 'Solanum betaceum' })

    expect(result.changed).to eq 1
    expect(plant.reload.scientific_name).to eq 'Solanum betaceum'
  end
end
