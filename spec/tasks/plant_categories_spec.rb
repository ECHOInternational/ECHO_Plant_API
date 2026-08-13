# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EcCategoryImporter do
  let(:org) { create(:organization, :real) }
  let!(:principal) do
    Principal.create!(kind: 'service', email: 'echo@echonet.org',
                      identity_issuer: 'spec')
  end
  let(:uuid) { SecureRandom.uuid }

  def importer(apply: true)
    described_class.new(organization: org, principal: principal,
                        owner_email: 'echo@echonet.org', apply: apply)
  end

  def category_row(id = uuid, name = 'Bamboo')
    { 'uuid' => id, 'translations' => { 'en' => { 'name' => name, 'description' => '' } } }
  end

  it 'creates a missing category with its translated name' do
    result = importer.import([category_row], {})

    expect(result.categories_created).to eq 1
    expect(Category.find(uuid).name).to eq 'Bamboo'
  end

  it 'leaves an existing category alone' do
    importer.import([category_row], {})
    result = importer.import([category_row(uuid, 'Renamed')], {})

    expect(result.categories_present).to eq 1
    expect(Category.find(uuid).name).to eq 'Bamboo'
  end

  it 'links a plant to a category' do
    plant = create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
    result = importer.import([category_row], { plant.id => [uuid] })

    expect(result.links_created).to eq 1
    expect(plant.reload.category_ids).to include uuid
  end

  it 'is additive: an existing link is counted, not duplicated' do
    plant = create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
    importer.import([category_row], { plant.id => [uuid] })
    result = importer.import([category_row], { plant.id => [uuid] })

    expect(result.links_present).to eq 1
    expect(result.links_created).to eq 0
    expect(plant.reload.category_ids.count(uuid)).to eq 1
  end

  it 'reports a plant it has never heard of instead of failing' do
    result = importer.import([category_row], { SecureRandom.uuid => [uuid] })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  # A dry run must count links belonging to categories it is about to create,
  # or it under-reports by the whole membership of every new category.
  it 'counts links for a not-yet-created category during a dry run' do
    plant = create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
    result = importer(apply: false).import([category_row], { plant.id => [uuid] })

    expect(result.categories_created).to eq 1
    expect(result.links_created).to eq 1
    expect(Category.exists?(uuid)).to be false
  end
end
