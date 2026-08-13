# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EcCommonNameSync do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  def sync(plants, apply: true)
    described_class.new(apply: apply).sync(plants)
  end

  def row(name, language: 'EN', primary: false, location: nil)
    { 'name' => name, 'language' => language, 'primary' => primary,
      'location' => location }
  end

  it 'creates a missing common name' do
    result = sync({ plant.id => [row('Baobab', primary: true)] })

    expect(result.created).to eq 1
    cn = plant.common_names.first
    expect([cn.name, cn.language, cn.primary]).to eq ['Baobab', 'EN', true]
  end

  it 'matches an existing name case-insensitively rather than duplicating it' do
    CommonName.create!(plant: plant, name: 'Baobab', language: 'EN', primary: false)
    result = sync({ plant.id => [row('baobab', primary: true)] })

    expect(result.created).to eq 0
    expect(result.present).to eq 1
    expect(plant.common_names.count).to eq 1
  end

  # The API only uses a language when a primary is set in it, otherwise falling
  # back to English. Setting the flag is what makes a translated name reachable.
  it 'sets the primary flag on an existing name' do
    cn = CommonName.create!(plant: plant, name: 'Mkate wa nyani', language: 'SW',
                            primary: false)
    result = sync({ plant.id => [row('Mkate wa nyani', language: 'SW', primary: true)] })

    expect(result.primary_set).to eq 1
    expect(cn.reload.primary).to be true
  end

  it 'clears a primary flag the source no longer marks' do
    cn = CommonName.create!(plant: plant, name: 'Baobab', language: 'EN', primary: true)
    result = sync({ plant.id => [row('Baobab', primary: false)] })

    expect(result.primary_cleared).to eq 1
    expect(cn.reload.primary).to be false
  end

  # Names match case-insensitively, so these are the same name. ECHOcommunity's
  # casing is the curated one; leaving the API holding a variant means that
  # variant gets pushed back to ECHOcommunity by the title sync.
  it 'adopts ECHOcommunity casing for an existing name' do
    cn = CommonName.create!(plant: plant, name: 'velvet bean', language: 'EN',
                            primary: true)
    result = sync({ plant.id => [row('Velvet Bean', primary: true)] })

    expect(result.recased).to eq 1
    expect(result.created).to eq 0
    expect(cn.reload.name).to eq 'Velvet Bean'
  end

  it 'reports a plant it has never heard of instead of failing' do
    result = sync({ SecureRandom.uuid => [row('Baobab')] })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  it 'writes nothing when not applying' do
    result = sync({ plant.id => [row('Baobab', primary: true)] }, apply: false)

    expect(result.created).to eq 1
    expect(plant.common_names.count).to eq 0
  end
end
