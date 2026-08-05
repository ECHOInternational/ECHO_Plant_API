# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::DiffBuilder, versioning: true do
  def last_version(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id).last
  end

  def build(record)
    described_class.new(last_version(record)).call
  end

  it 'renders a scalar column change under its camelCase graphql name' do
    plant = create(:plant, scientific_name: 'Old Name')
    plant.update!(scientific_name: 'New Name')

    expect(build(plant)).to include(
      { field: 'scientificName', locale: nil, before: 'Old Name', after: 'New Name' }
    )
  end

  it 'renders booleans as true/false' do
    plant = create(:plant, has_edible_green_leaves: false)
    plant.update!(has_edible_green_leaves: true)

    expect(build(plant)).to include(
      { field: 'hasEdibleGreenLeaves', locale: nil, before: 'false', after: 'true' }
    )
  end

  it 'renders enums as their graphql names' do
    plant = create(:plant, life_cycle: 'annual')
    plant.update!(life_cycle: 'perennial')

    expect(build(plant)).to include(
      { field: 'lifeCycle', locale: nil, before: 'ANNUAL', after: 'PERENNIAL' }
    )
  end

  it 'renders ranges as postgres range literals' do
    plant = create(:plant, ph_range: '[1.0,2.0]')
    plant.update!(ph_range: '[3.0,4.0]')

    change = build(plant).find { |c| c[:field] == 'phRange' }
    expect(change[:before]).to eq '[1.0,2.0]'
    expect(change[:after]).to eq '[3.0,4.0]'
  end

  it 'renders visibility as its enum name' do
    plant = create(:plant, :private)
    plant.update!(visibility: :public)

    expect(build(plant)).to include(
      { field: 'visibility', locale: nil, before: 'PRIVATE', after: 'PUBLIC' }
    )
  end

  it 'renders visibility from the raw integers PaperTrail stores when the item is gone' do
    # PaperTrail's enum deserialization is skipped whenever `item` resolves to
    # nil (see version_concern.rb: "unless item.nil?" guards the attribute
    # serializer call, with the comment "item returns nil if event is
    # destroy"). Destroy versions hit this path in production. We reproduce it
    # here on an update version by deleting the row out from under it, which
    # makes `item` nil the same way a destroy does.
    plant = create(:plant, :private)
    plant.update!(visibility: :public)
    version = last_version(plant)

    Plant.where(id: plant.id).delete_all
    expect(version.changeset['visibility']).to eq [0, 1] # sanity: raw integers, not enum strings

    change = described_class.new(version).call.find { |c| c[:field] == 'visibility' }
    expect(change).to eq(field: 'visibility', locale: nil, before: 'PRIVATE', after: 'PUBLIC')
  end

  it 'flattens translations into one entry per locale and attribute' do
    plant = create(:plant)
    Mobility.with_locale(:es) { plant.update!(uses: 'Usos nuevos') }

    expect(build(plant)).to include(
      { field: 'uses', locale: 'es', before: nil, after: 'Usos nuevos' }
    )
  end

  it 'skips noise columns' do
    plant = create(:plant, scientific_name: 'Old Name')
    plant.update!(scientific_name: 'New Name')

    fields = build(plant).map { |c| c[:field] }
    expect(fields).not_to include('updatedAt', 'createdAt', 'translations', 'publicationState')
  end

  it 'returns an empty list for a version with no parsable changes' do
    plant = create(:plant)
    version = last_version(plant)
    version.update_columns(object_changes: nil)

    expect(described_class.new(version).call).to eq []
  end

  it 'resolves an ownership-transfer organization id to the organization name' do
    plant = create(:plant)
    original_owner_name = Organization.find(plant.owner_organization_id).name
    new_org = create(:organization, :real)

    plant.update!(owner_organization_id: new_org.id)

    change = build(plant).find { |c| c[:field] == 'ownerOrganizationId' }
    expect(change).to eq(
      field: 'ownerOrganizationId', locale: nil, before: original_owner_name, after: new_org.name
    )
  end

  it 'falls back to an unknown-organization label when the referenced organization row is gone' do
    plant = create(:plant)
    vanished_org = create(:organization, :real)
    final_org = create(:organization, :real)

    plant.update!(owner_organization_id: vanished_org.id)
    plant.update!(owner_organization_id: final_org.id)
    vanished_org.destroy!

    change = build(plant).find { |c| c[:field] == 'ownerOrganizationId' }
    expect(change).to eq(
      field: 'ownerOrganizationId', locale: nil, before: 'Unknown organization', after: final_org.name
    )
  end

  it 'resolves a created_by_principal_id change to the principal display name' do
    original_creator = create(:principal)
    plant = create(:plant, created_by_principal_id: original_creator.id)
    new_creator = create(:principal)

    plant.update!(created_by_principal_id: new_creator.id)

    change = build(plant).find { |c| c[:field] == 'createdByPrincipalId' }
    expect(change).to eq(
      field: 'createdByPrincipalId', locale: nil, before: original_creator.display_name, after: new_creator.display_name
    )
  end

  it 'falls back to an unknown-user label when the referenced principal row is gone' do
    original_creator = create(:principal)
    plant = create(:plant, created_by_principal_id: original_creator.id)
    new_creator = create(:principal)

    plant.update!(created_by_principal_id: new_creator.id)
    original_creator.destroy!

    change = build(plant).find { |c| c[:field] == 'createdByPrincipalId' }
    expect(change).to eq(
      field: 'createdByPrincipalId', locale: nil, before: 'Unknown user', after: new_creator.display_name
    )
  end
end
