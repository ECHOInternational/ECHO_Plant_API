# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyNameNormalizer do
  def candidates(raw)
    described_class.call(raw)[:candidates]
  end

  it 'passes a clean name through' do
    expect(candidates('Fabaceae')).to eq(['Fabaceae'])
  end

  it 'treats a blank value as having no candidates' do
    expect(described_class.call(nil)[:kind]).to eq(:blank)
    expect(described_class.call('   ')[:kind]).to eq(:blank)
  end

  it 'strips leading and trailing whitespace' do
    expect(candidates(' Lauraceae')).to eq(['Lauraceae'])
    expect(candidates('Arecaceae ')).to eq(['Arecaceae'])
  end

  it 'strips a trailing tab' do
    expect(candidates("Musaceae\t")).to eq(['Musaceae'])
  end

  # Production uses EN DASH (U+2013) for this, never an ASCII hyphen.
  it 'drops a common name appended after an en dash' do
    expect(candidates('Cucurbitaceae – Gourd')).to eq(['Cucurbitaceae'])
    expect(candidates('Solanaceae – Nightshade')).to eq(['Solanaceae'])
  end

  it 'drops a common name appended after a run of spaces' do
    expect(candidates('Poaceae   Grass')).to eq(['Poaceae'])
    expect(candidates('Apiaceae   Celery')).to eq(['Apiaceae'])
  end

  it 'drops a common name appended after a single space' do
    expect(candidates('Malvaceae Mallow')).to eq(['Malvaceae'])
  end

  it 'splits a parenthetical alternative into both names' do
    expect(candidates('Asteraceae (Compositae)')).to eq(%w[Asteraceae Compositae])
  end

  it 'splits on the word Or' do
    expect(candidates('Fabaceae Or Leguminosae')).to eq(%w[Fabaceae Leguminosae])
  end

  it 'splits on a comma' do
    expect(candidates('Fabaceae, Legumininosae')).to eq(%w[Fabaceae Legumininosae])
  end

  it 'splits a multi-family string' do
    expect(candidates('Malvaceae  Bombacaceae   Durionaceae'))
      .to eq(%w[Malvaceae Bombacaceae Durionaceae])
  end

  it 'drops a Spanish label appended after an en dash' do
    expect(candidates('Cucurbitaceae – Familia de las Calabazas ')).to eq(['Cucurbitaceae'])
  end

  it 'keeps an unrecognisable value intact for fuzzy matching' do
    expect(candidates('Fabacaea')).to eq(['Fabacaea'])
    expect(described_class.call('Fabacaea')[:kind]).to eq(:unrecognised)
  end
end
