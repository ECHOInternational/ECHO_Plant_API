# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_translation_backfill')

RSpec.describe EcTranslationBackfill do
  let(:org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  def backfill(plants, apply: true)
    described_class.new(apply: apply).backfill(plants)
  end

  it 'writes text into a locale the API does not have' do
    result = backfill({ plant.id => { 'es' => { 'uses' => 'Usos en español' } } })

    expect(result.written).to eq 1
    expect(Mobility.with_locale(:es) { plant.reload.uses }).to eq 'Usos en español'
  end

  # The whole point: this must not become an overwrite.
  it 'never overwrites text the API already holds' do
    Mobility.with_locale(:es) { plant.update!(uses: 'Texto existente') }

    result = backfill({ plant.id => { 'es' => { 'uses' => 'Texto entrante' } } })

    expect(result.written).to eq 0
    expect(result.differs).to eq 1
    expect(Mobility.with_locale(:es) { plant.reload.uses }).to eq 'Texto existente'
  end

  it 'reports what differs, with enough detail to review it' do
    Mobility.with_locale(:es) { plant.update!(uses: 'corto') }
    result = backfill({ plant.id => { 'es' => { 'uses' => 'un texto mucho más largo' } } })

    conflict = result.conflicts.first
    expect(conflict).to include(plant: plant.id, locale: 'es', attribute: 'uses')
    expect(conflict[:api_length]).to eq 5
    expect(conflict[:ec_length]).to eq 24
  end

  it 'counts an identical value as already present, not a conflict' do
    Mobility.with_locale(:es) { plant.update!(uses: 'Mismo texto') }
    result = backfill({ plant.id => { 'es' => { 'uses' => 'Mismo texto' } } })

    expect(result.already_present).to eq 1
    expect(result.differs).to eq 0
  end

  # An empty ECHOcommunity field must not manufacture an empty translation, and
  # with it the claim that the record exists in that language.
  it 'never writes a blank value' do
    result = backfill({ plant.id => { 'es' => { 'uses' => '   ' } } })

    expect(result.blank_skipped).to eq 1
    expect(result.written).to eq 0
    expect(plant.reload.translations).not_to have_key 'es'
  end

  it 'leaves other locales untouched' do
    Mobility.with_locale(:en) { plant.update!(uses: 'English text') }
    backfill({ plant.id => { 'es' => { 'uses' => 'Texto español' } } })

    plant.reload
    expect(Mobility.with_locale(:en) { plant.uses }).to eq 'English text'
    expect(Mobility.with_locale(:es) { plant.uses }).to eq 'Texto español'
  end

  it 'ignores an attribute this data source does not govern' do
    result = backfill({ plant.id => { 'es' => { 'scientific_name' => 'Nope' } } })

    expect(result.written).to eq 0
    expect(plant.reload.scientific_name).not_to eq 'Nope'
  end

  it 'handles several locales in one payload' do
    result = backfill({ plant.id => { 'es' => { 'uses' => 'Usos' },
                                      'fr' => { 'uses' => 'Utilisations' } } })

    expect(result.written).to eq 2
    plant.reload
    expect(Mobility.with_locale(:es) { plant.uses }).to eq 'Usos'
    expect(Mobility.with_locale(:fr) { plant.uses }).to eq 'Utilisations'
  end

  # Regression: Mobility's fallbacks plugin makes a read of a missing locale
  # return the :en value, so asking the reader "does Spanish have this?" always
  # answers yes for any plant with English text. Every value then looks like a
  # conflict and the backfill writes nothing - silently doing nothing at all,
  # for exactly the 1,229 values it exists to move.
  it 'writes Spanish even when English is present and fallbacks would mask it' do
    Mobility.with_locale(:en) { plant.update!(uses: 'English text') }
    expect(Mobility.with_locale(:es) { plant.reload.uses })
      .to eq('English text'), 'if this fails, fallbacks are off and the trap is gone'

    result = backfill({ plant.id => { 'es' => { 'uses' => 'Texto español' } } })

    expect(result.written).to eq(1), 'the fallback must not be mistaken for stored Spanish'
    expect(result.differs).to eq 0
    expect(plant.reload.translations['es']['uses']).to eq 'Texto español'
  end

  # A review pile that is mostly markup trains its reader to skim. The first
  # staging run reported 473 differences of which 452 were entities and
  # whitespace; only 21 said anything different.
  describe 'markup differences' do
    it 'treats text that differs only in markup as already present' do
      Mobility.with_locale(:es) { plant.update!(uses: '<p>Uso&nbsp;principal</p>') }

      result = backfill({ plant.id => { 'es' => { 'uses' => '<div>Uso principal</div>' } } })

      expect(result.already_present).to eq 1
      expect(result.differs).to eq(0), 'markup alone is not an editorial disagreement'
    end

    it 'keeps the API copy rather than rewriting its punctuation' do
      Mobility.with_locale(:es) { plant.update!(uses: '<p>Uso&nbsp;principal</p>') }
      backfill({ plant.id => { 'es' => { 'uses' => '<div>Uso principal</div>' } } })

      expect(plant.reload.translations['es']['uses']).to eq '<p>Uso&nbsp;principal</p>'
    end

    it 'still reports a genuine wording difference' do
      Mobility.with_locale(:es) { plant.update!(uses: '<p>Uso principal</p>') }

      result = backfill({ plant.id => { 'es' => { 'uses' => '<p>Otro uso completamente</p>' } } })

      expect(result.differs).to eq 1
    end
  end

  it 'skips a plant that is not in this database' do
    result = backfill({ SecureRandom.uuid => { 'es' => { 'uses' => 'x' } } })

    expect(result.missing_plants).to eq 1
    expect(result.failed).to eq 0
  end

  it 'writes nothing on a dry run but still reports what would be written' do
    result = backfill({ plant.id => { 'es' => { 'uses' => 'Usos' } } }, apply: false)

    expect(result.written).to eq 1
    expect(plant.reload.translations).not_to have_key 'es'
  end
end
