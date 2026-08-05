# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'families query', type: :request do
  before do
    Family.importing do
      create(:family, name: 'Fabaceae', kingdom: 'Plantae', plant_type: 'Angiosperms')
      create(:family, name: 'Poaceae', kingdom: 'Plantae', plant_type: 'Angiosperms')
      create(:family, name: 'Russulaceae', kingdom: 'Fungi', plant_type: 'Fungi')
    end
  end

  def execute(query)
    PlantApiSchema.execute(query, context: { current_user: nil })
  end

  it 'is readable without a token and reports a total count' do
    result = execute('{ families(first: 10) { totalCount nodes { name } } }')
    expect(result['errors']).to be_nil
    expect(result.dig('data', 'families', 'totalCount')).to eq(3)
  end

  it 'orders by name so paging is stable' do
    result = execute('{ families(first: 10) { nodes { name } } }')
    names = result.dig('data', 'families', 'nodes').map { |n| n['name'] }
    expect(names).to eq(%w[Fabaceae Poaceae Russulaceae])
  end

  it 'filters by a case-insensitive partial name' do
    result = execute('{ families(first: 10, name: "acea") { totalCount } }')
    expect(result.dig('data', 'families', 'totalCount')).to eq(3)
  end

  it 'filters by kingdom' do
    result = execute('{ families(first: 10, kingdom: "Fungi") { nodes { name } } }')
    expect(result.dig('data', 'families', 'nodes').map { |n| n['name'] }).to eq(['Russulaceae'])
  end

  it 'filters by plant type' do
    result = execute('{ families(first: 10, plantType: "Angiosperms") { totalCount } }')
    expect(result.dig('data', 'families', 'totalCount')).to eq(2)
  end

  it 'excludes superseded families by default' do
    Family.importing { create(:family, name: 'Tiliaceae', status: 'superseded') }
    result = execute('{ families(first: 10) { totalCount } }')
    expect(result.dig('data', 'families', 'totalCount')).to eq(3)
  end
end
