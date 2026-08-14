# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlantDescriptionSync do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id,
                   scientific_name: 'Acacia torulosa')
  end

  def sync(plants, apply: true)
    described_class.new(apply: apply).sync(plants)
  end

  before { Mobility.with_locale(:en) { plant.update!(description: 'group prose') } }

  it 'writes the description for the named locale' do
    result = sync({ plant.id => { 'en' => { 'description' => 'species prose' } } })

    expect(result.changed).to eq 1
    expect(Mobility.with_locale(:en) { plant.reload.description }).to eq 'species prose'
  end

  it 'writes info_sheet_description too' do
    result = sync({ plant.id => { 'en' => { 'info_sheet_description' => 'sheet text' } } })

    expect(result.changed).to eq 1
    expect(Mobility.with_locale(:en) { plant.reload.info_sheet_description })
      .to eq 'sheet text'
  end

  # This must never become a general-purpose writer for a record the API owns.
  it 'refuses to write a field outside the allowlist' do
    result = sync({ plant.id => { 'en' => { 'scientific_name' => 'Nope' } } })

    expect(result.failed).to eq 1
    expect(result.errors.first).to include 'refusing to write'
    expect(plant.reload.scientific_name).to eq 'Acacia torulosa'
  end

  it 'never erases text with a blank value' do
    result = sync({ plant.id => { 'en' => { 'description' => '  ' } } })

    expect(result.blank_skipped).to eq 1
    expect(result.changed).to eq 0
    expect(Mobility.with_locale(:en) { plant.reload.description }).to eq 'group prose'
  end

  it 'leaves locales the payload does not name alone' do
    Mobility.with_locale(:fr) { plant.update!(description: 'texte') }

    sync({ plant.id => { 'en' => { 'description' => 'species prose' } } })

    expect(Mobility.with_locale(:fr) { plant.reload.description }).to eq 'texte'
  end

  it 'reports a plant that is not in this database instead of failing' do
    result = sync({ SecureRandom.uuid => { 'en' => { 'description' => 'x' } } })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  it 'counts an already-correct value as unchanged' do
    result = sync({ plant.id => { 'en' => { 'description' => 'group prose' } } })

    expect(result.unchanged).to eq 1
    expect(result.changed).to eq 0
  end

  it 'changes nothing on a dry run but still reports what would change' do
    result = sync({ plant.id => { 'en' => { 'description' => 'species prose' } } },
                  apply: false)

    expect(result.changed).to eq 1
    expect(result.changes.first).to include 'Acacia torulosa'
    expect(Mobility.with_locale(:en) { plant.reload.description }).to eq 'group prose'
  end
end
