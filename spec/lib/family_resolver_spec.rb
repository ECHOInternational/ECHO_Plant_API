# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyResolver do
  subject(:resolver) { described_class.new }

  before do
    Family.importing do
      create(:family, name: 'Fabaceae')
      create(:family, name: 'Cucurbitaceae')
    end
  end

  it 'resolves a name already in the local list without any network call' do
    expect(resolver).not_to receive(:gbif_spelling)
    result = resolver.resolve('Fabaceae')
    expect(result[:family].name).to eq('Fabaceae')
    expect(result[:via]).to eq(:local)
  end

  it 'uses a GBIF spelling correction and re-resolves locally' do
    allow(resolver).to receive(:gbif_spelling)
      .with('Curcurbitaceae')
      .and_return({ spelling: 'Cucurbitaceae', confidence: 5 })

    result = resolver.resolve('Curcurbitaceae')
    expect(result[:family].name).to eq('Cucurbitaceae')
    expect(result[:via]).to eq(:gbif_corrected)
    expect(result[:confidence]).to eq(5)
  end

  it 'returns no family when nothing resolves' do
    allow(resolver).to receive(:gbif_spelling).and_return(nil)
    expect(resolver.resolve('Leguminaceae')[:family]).to be_nil
  end

  # Without a kingdom and rank guard, GBIF answers this typo with Hiatellidae,
  # a bivalve mollusc family, at confidence 0.
  it 'refuses an out-of-scope kingdom suggestion' do
    expect(resolver.send(:acceptable_gbif_match?,
                         { 'family' => 'Hiatellidae', 'kingdom' => 'Animalia',
                           'matchType' => 'FUZZY' })).to be false
    expect(resolver.send(:acceptable_gbif_match?,
                         { 'family' => 'Rosaceae', 'kingdom' => 'Plantae',
                           'matchType' => 'FUZZY' })).to be true
  end
end
