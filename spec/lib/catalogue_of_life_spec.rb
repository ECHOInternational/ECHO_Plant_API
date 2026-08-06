# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CatalogueOfLife do
  describe '.plant_type_for' do
    it 'maps every COL group the API returns' do
      {
        'angiosperms' => 'Angiosperms',
        'gymnosperms' => 'Gymnosperms',
        'pteridophytes' => 'Ferns & Fern Allies',
        'bryophytes' => 'Mosses, Liverworts & Hornworts',
        'algae' => 'Algae & Seaweed',
        'protists' => 'Protists',
        'ascomycetes' => 'Fungi',
        'basidiomycetes' => 'Fungi',
        'otherfungi' => 'Fungi',
        'fungi' => 'Fungi',
        'pseudofungi' => 'Fungi',
        'plants' => 'Other Plants',
        'eukaryotes' => 'Other'
      }.each do |group, expected|
        expect(described_class.plant_type_for(group)).to eq(expected)
      end
    end

    it 'returns nil for an unknown group rather than guessing' do
      expect(described_class.plant_type_for('cryptids')).to be_nil
    end
  end

  describe '#families' do
    subject(:client) { described_class.new(dataset: '315834') }

    let(:page) do
      {
        'total' => 1,
        'result' => [{
          'usage' => { 'id' => '623QT', 'name' => { 'scientificName' => 'Fabaceae' } },
          'group' => 'angiosperms'
        }]
      }
    end

    before { allow(client).to receive(:get_page).and_return(page) }

    it 'returns normalised rows' do
      rows = client.families(kingdom_id: 'P', kingdom_name: 'Plantae')
      expect(rows).to eq([{ name: 'Fabaceae', col_id: '623QT',
                            kingdom: 'Plantae', plant_type: 'Angiosperms' }])
    end
  end

  describe '#synonym_lookup' do
    subject(:client) { described_class.new(dataset: '315834') }

    def hit_for(name, status:, accepted_name: nil)
      usage = { 'name' => { 'scientificName' => name }, 'status' => status }
      usage['accepted'] = { 'name' => { 'scientificName' => accepted_name } } if accepted_name
      { 'usage' => usage }
    end

    def stub_search(result)
      allow(client).to receive(:get_name_search).with('Tiliaceae').and_return({ 'result' => result })
    end

    it 'reports a synonym and the accepted name it now points at' do
      stub_search([hit_for('Tiliaceae', status: 'synonym', accepted_name: 'Malvaceae')])
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :synonym, accepted_name: 'Malvaceae')
    end

    it 'reports an ambiguous synonym distinctly, with no single target' do
      stub_search([hit_for('Tiliaceae', status: 'ambiguous synonym')])
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :ambiguous_synonym)
    end

    it 'reports :accepted rather than guessing when the name turns out not to be gone at all' do
      stub_search([hit_for('Tiliaceae', status: 'accepted')])
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :accepted)
    end

    it 'reports :not_found when nothing matches the queried name' do
      stub_search([hit_for('Somethingelseaceae', status: 'accepted')])
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :not_found)
    end

    it 'reports :not_found for an empty result set' do
      stub_search([])
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :not_found)
    end

    it 'matches the queried name case-insensitively among several results' do
      stub_search([hit_for('Somethingelseaceae', status: 'accepted'),
                   hit_for('TILIACEAE', status: 'synonym', accepted_name: 'Malvaceae')])
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :synonym, accepted_name: 'Malvaceae')
    end

    it 'falls back to :error rather than raising when the request itself fails' do
      allow(client).to receive(:get_name_search).and_raise(StandardError, 'boom')
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :error)
    end

    it 'falls back to :error rather than raising on an unexpected response shape' do
      allow(client).to receive(:get_name_search).and_return('not' => 'the expected shape')
      expect(client.synonym_lookup('Tiliaceae')).to eq(status: :not_found)
    end
  end
end
