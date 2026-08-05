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
end
