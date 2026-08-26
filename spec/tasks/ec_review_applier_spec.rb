# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_review_applier')

RSpec.describe EcReviewApplier do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  def ruling(attribute: 'uses', locale: 'es', value: 'Texto de ECHOcommunity',
             plant_id: plant.id)
    { 'plant_id' => plant_id, 'locale' => locale,
      'attribute' => attribute, 'value' => value }
  end

  def apply(rulings, apply: true)
    described_class.new(apply: apply).apply(rulings)
  end

  # The one thing the backfill must never do is the one thing this exists for.
  it 'overwrites text the API already holds' do
    Mobility.with_locale(:es) { plant.update!(uses: 'Texto viejo del API') }

    result = apply([ruling])

    expect(result.applied).to eq 1
    expect(Mobility.with_locale(:es) { plant.reload.uses })
      .to eq 'Texto de ECHOcommunity'
  end

  it 'is idempotent: a second run changes nothing' do
    Mobility.with_locale(:es) { plant.update!(uses: 'Texto viejo') }
    apply([ruling])

    result = apply([ruling])

    expect(result.applied).to eq 0
    expect(result.already_applied).to eq 1
  end

  it 'treats markup-only differences as already applied' do
    Mobility.with_locale(:es) { plant.update!(uses: '<p>Texto de&nbsp;ECHOcommunity</p>') }

    result = apply([ruling(value: 'Texto de ECHOcommunity')])

    expect(result.applied).to eq 0
    expect(result.already_applied).to eq 1
    # The API keeps its own copy, punctuation and markup included.
    expect(plant.reload.translations['es']['uses'])
      .to eq '<p>Texto de&nbsp;ECHOcommunity</p>'
  end

  it 'refuses a blank value — a ruling cannot blank a field' do
    Mobility.with_locale(:es) { plant.update!(uses: 'Texto que debe quedarse') }

    result = apply([ruling(value: '  ')])

    expect(result.blank_refused).to eq 1
    expect(Mobility.with_locale(:es) { plant.reload.uses })
      .to eq 'Texto que debe quedarse'
  end

  it 'refuses attributes outside the governed narrative set' do
    result = apply([ruling(attribute: 'scientific_name', value: 'Hackus plantus')])

    expect(result.not_governed).to eq 1
    expect(result.applied).to eq 0
  end

  it 'counts a plant this database does not have' do
    result = apply([ruling(plant_id: SecureRandom.uuid)])

    expect(result.missing_plants).to eq 1
  end

  it 'writes nothing on a dry run, but reports what it would change' do
    Mobility.with_locale(:es) { plant.update!(uses: 'Texto viejo') }

    result = apply([ruling], apply: false)

    expect(result.applied).to eq 1
    expect(result.changes.first).to include(plant.id).and include('uses')
    expect(Mobility.with_locale(:es) { plant.reload.uses }).to eq 'Texto viejo'
  end

  it 'writes only the named locale and attribute, nothing else on the record' do
    Mobility.with_locale(:es) { plant.update!(uses: 'viejo', cultivation: 'cultivo') }
    en_uses = Mobility.with_locale(:en) { plant.uses }

    apply([ruling])

    reloaded = plant.reload
    expect(Mobility.with_locale(:es) { reloaded.cultivation }).to eq 'cultivo'
    expect(Mobility.with_locale(:en) { reloaded.uses }).to eq en_uses
  end
end
