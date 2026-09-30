# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommonNameCorrections::PlantFinder do
  # Stands in for CatalogueOfLife so every branch runs without the network.
  def finder_for(status:, accepted_name: nil)
    lookup = { status: status }
    lookup[:accepted_name] = accepted_name if accepted_name
    described_class.new(catalogue_of_life: instance_double(CatalogueOfLife, synonym_lookup: lookup))
  end

  it 'finds a plant by its exact scientific name without asking Catalogue of Life' do
    plant = create(:plant, scientific_name: 'Acacia tumida')
    # Any COL call would raise, because the double declares no such message.
    finder = described_class.new(catalogue_of_life: instance_double(CatalogueOfLife))

    found = finder.call('Acacia tumida')

    expect(found.plant).to eq(plant)
    expect(found.via_synonym).to be_falsey
  end

  it 'finds a plant whose stored name differs only in case' do
    plant = create(:plant, scientific_name: 'Acacia Tumida')
    finder = described_class.new(catalogue_of_life: instance_double(CatalogueOfLife))

    expect(finder.call('acacia tumida').plant).to eq(plant)
  end

  it 'finds the plant filed under the accepted name when the given name is a synonym' do
    plant = create(:plant, scientific_name: 'Vachellia tumida')
    finder = finder_for(status: :synonym, accepted_name: 'Vachellia tumida')

    found = finder.call('Acacia tumida')

    expect(found.plant).to eq(plant)
    expect(found.via_synonym).to be true
    expect(found.line).to include('synonym').and include('Vachellia tumida')
  end

  it 'reports an ambiguous synonym rather than choosing a successor' do
    create(:plant, scientific_name: 'Vachellia tumida')
    found = finder_for(status: :ambiguous_synonym).call('Acacia tumida')

    expect(found.plant).to be_nil
    expect(found.line).to include('ambiguous synonym')
  end

  it 'says the plant may be filed under a synonym when the name is itself accepted' do
    found = finder_for(status: :accepted).call('Acacia tumida')

    expect(found.plant).to be_nil
    expect(found.line).to include('either absent or filed under a synonym')
  end

  it 'reports when neither the given name nor its accepted name matches a plant' do
    found = finder_for(status: :synonym, accepted_name: 'Vachellia tumida').call('Acacia tumida')

    expect(found.plant).to be_nil
    expect(found.line).to include('Vachellia tumida').and include('no plant is filed under either')
  end

  it 'reports a name Catalogue of Life does not know' do
    found = finder_for(status: :not_found).call('Acacia nonexistentia')

    expect(found.plant).to be_nil
    expect(found.line).to include('unknown to Catalogue of Life')
  end

  it 'reports a failed lookup rather than raising' do
    found = finder_for(status: :error).call('Acacia tumida')

    expect(found.plant).to be_nil
    expect(found.line).to include('lookup failed')
  end
end
