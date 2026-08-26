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

  def range_ruling(low: 1500, high: nil, attribute: 'optimal_altitude_range',
                   plant_id: plant.id)
    { 'plant_id' => plant_id, 'attribute' => attribute, 'lo' => low, 'hi' => high }
  end

  # int4range canonicalizes an inclusive write to an exclusive upper bound
  # ([500,2000] -> [500,2001)), and an open bound reads back as Infinity —
  # the same storage behaviour D-053 documented. Expectations match storage.
  it 'writes an open-ended range over nothing (D-055)' do
    result = apply([range_ruling])

    expect(result.applied).to eq 1
    expect(plant.reload.optimal_altitude_range).to eq(1500...Float::INFINITY)
  end

  it 'writes a bounded range over nothing' do
    apply([range_ruling(low: 500, high: 2000)])

    expect(plant.reload.optimal_altitude_range).to eq(500...2001)
  end

  it 'refuses to touch a range the API already holds — additive only' do
    plant.update!(optimal_altitude_range: 0..900)

    result = apply([range_ruling])

    expect(result.range_occupied).to eq 1
    expect(result.applied).to eq 0
    expect(plant.reload.optimal_altitude_range).to eq(0...901)
  end

  it 'refuses a range ruling with no lower bound' do
    result = apply([range_ruling(low: nil)])

    expect(result.blank_refused).to eq 1
  end

  it 'writes no range on a dry run' do
    result = apply([range_ruling], apply: false)

    expect(result.applied).to eq 1
    expect(plant.reload.optimal_altitude_range).to be_nil
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
