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
end
