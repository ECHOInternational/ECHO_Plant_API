# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/koppen_zone_seeder')

RSpec.describe 'koppenZones' do
  let(:user) { build(:user, :superadmin) }

  before { KoppenZoneSeeder.new(apply: true).seed }

  def query(args = '', selection: 'code level authoritative')
    result = PlantApiSchema.execute(
      "{ koppenZones#{args} { totalCount edges { node { #{selection} } } } }",
      context: { current_user: user }
    )
    raise result['errors'].inspect if result['errors']

    result['data']['koppenZones']
  end

  it 'returns every zone' do
    expect(query['totalCount']).to eq 45
  end

  it 'filters by level' do
    data = query('(level: "group")')

    expect(data['totalCount']).to eq 5
    expect(data['edges'].map { |e| e.dig('node', 'code') }).to contain_exactly(*%w[A B C D E])
  end

  it 'filters by whether the zone appears in Beck 2018' do
    expect(query('(authoritative: true)')['totalCount']).to eq 35
    expect(query('(authoritative: false)')['totalCount']).to eq 10
  end

  it 'matches a code case-insensitively' do
    data = query('(code: "cfa")')

    expect(data['totalCount']).to eq 1
    expect(data['edges'].first.dig('node', 'code')).to eq 'Cfa'
  end

  it 'exposes the hierarchy in both directions' do
    data = query('(code: "Cf")', selection: 'code parent { code } children { code }')
    node = data['edges'].first['node']

    expect(node.dig('parent', 'code')).to eq 'C'
    expect(node['children'].map { |c| c['code'] }).to contain_exactly('Cfa', 'Cfb', 'Cfc')
  end

  it 'returns the translated name' do
    data = query('(code: "Aw")', selection: 'code name')

    expect(data['edges'].first.dig('node', 'name')).to eq 'Tropical Savanna Climate'
  end

  # The lookup is reference data behind a public read, like the other
  # taxonomies; a tokenless request must still resolve it.
  it 'is readable without a user' do
    result = PlantApiSchema.execute('{ koppenZones { totalCount } }', context: {})

    expect(result['errors']).to be_nil
    expect(result.dig('data', 'koppenZones', 'totalCount')).to eq 45
  end
end
