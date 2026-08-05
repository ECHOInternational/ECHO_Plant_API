# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilySeedBankingLoader, type: :service do
  before do
    Family.importing do
      create(:family, name: 'Amaranthaceae')
      create(:family, name: 'Malvaceae')
    end
  end

  describe '.normalize_longevity' do
    # The source file splits one value across an en dash and a hyphen.
    it 'merges the two dash spellings of Low-Medium' do
      expect(described_class.normalize_longevity('Low–Medium')).to eq('low_medium')
      expect(described_class.normalize_longevity('Low-Medium')).to eq('low_medium')
    end

    it 'maps the simple values' do
      expect(described_class.normalize_longevity('High')).to eq('high')
      expect(described_class.normalize_longevity('Medium–High')).to eq('medium_high')
    end

    it 'returns nil for a blank' do
      expect(described_class.normalize_longevity('')).to be_nil
    end
  end

  describe '.normalize_storage' do
    it 'maps the four dominant values' do
      expect(described_class.normalize_storage('Orthodox')).to eq('orthodox')
      expect(described_class.normalize_storage('Recalcitrant')).to eq('recalcitrant')
      expect(described_class.normalize_storage('Variable')).to eq('variable')
      expect(described_class.normalize_storage('Mixed')).to eq('mixed')
    end

    it 'maps hedged variants to their category' do
      expect(described_class.normalize_storage('Mostly orthodox')).to eq('orthodox')
      expect(described_class.normalize_storage('Likely recalcitrant')).to eq('recalcitrant')
      expect(described_class.normalize_storage('Recalcitrant/intermediate')).to eq('intermediate')
    end

    it 'maps limited data to unknown' do
      expect(described_class.normalize_storage('Limited data')).to eq('unknown')
    end

    it 'returns nil for a blank' do
      expect(described_class.normalize_storage('')).to be_nil
    end
  end

  describe '.qualifier_from' do
    # "Mostly orthodox (onions, garlic, leeks)" loses real editorial content if
    # only the enum is kept, so the parenthetical is preserved in the notes.
    it 'extracts a parenthetical qualifier' do
      expect(described_class.qualifier_from('Mostly orthodox (onions, garlic, leeks)'))
        .to eq('onions, garlic, leeks')
    end

    it 'returns nil when there is none' do
      expect(described_class.qualifier_from('Orthodox')).to be_nil
    end
  end

  describe '#run' do
    let(:rows) do
      [{ 'family' => 'Amaranthaceae', 'storage_physiology' => 'Orthodox',
         'seed_longevity' => 'High', 'seed_banking_rank' => '5',
         'seed_banking_notes' => 'Highly suitable' },
       # A family COL treats as a synonym: its metadata must land on the
       # accepted family instead of being dropped.
       { 'family' => 'Chenopodiaceae', 'storage_physiology' => 'Orthodox',
         'seed_longevity' => 'Medium', 'seed_banking_rank' => '4',
         'seed_banking_notes' => 'Merged family' },
       { 'family' => 'Pomaceae', 'storage_physiology' => 'Orthodox',
         'seed_longevity' => 'High', 'seed_banking_rank' => '5',
         'seed_banking_notes' => 'No COL target' }]
    end

    it 'loads metadata onto a matching family' do
      described_class.new(rows: rows, redirects: {}, dry_run: false).run
      family = Family.find_by(name: 'Amaranthaceae')
      expect(family.storage_physiology).to eq('orthodox')
      expect(family.seed_longevity).to eq('high')
      expect(family.seed_banking_rank).to eq(5)
      expect(family.seed_banking_notes).to eq('Highly suitable')
    end

    it 'redirects a synonym onto its accepted family' do
      described_class.new(rows: rows, redirects: { 'Chenopodiaceae' => 'Amaranthaceae' },
                          dry_run: false).run
      expect(Family.find_by(name: 'Amaranthaceae').seed_banking_rank).to eq(4)
    end

    it 'reports the redirect that was applied' do
      report = described_class.new(rows: rows, redirects: { 'Chenopodiaceae' => 'Amaranthaceae' },
                                   dry_run: false).run
      expect(report.redirected).to eq([%w[Chenopodiaceae Amaranthaceae]])
    end

    it 'reports rather than guesses when there is no target' do
      report = described_class.new(rows: rows, redirects: {}, dry_run: false).run
      expect(report.unmatched).to include('Pomaceae')
    end

    it 'writes nothing on a dry run' do
      described_class.new(rows: rows, redirects: {}, dry_run: true).run
      expect(Family.find_by(name: 'Amaranthaceae').seed_banking_rank).to be_nil
    end

    it 'still reports what a dry run would have done, since nothing is written to inspect' do
      report = described_class.new(rows: rows, redirects: {}, dry_run: true).run
      expect(report.updated).to eq(['Amaranthaceae'])
      # Without a redirect, Chenopodiaceae has no family named that in the
      # scope, so it is unmatched here too -- the redirect map is what turns
      # it into a match, exercised separately above.
      expect(report.unmatched).to eq(%w[Chenopodiaceae Pomaceae])
    end

    it 'preserves a parenthetical storage qualifier in the notes rather than discarding it' do
      hedged_rows = [{ 'family' => 'Amaranthaceae',
                       'storage_physiology' => 'Mostly orthodox (onions, garlic, leeks)',
                       'seed_longevity' => 'Medium', 'seed_banking_rank' => '3',
                       'seed_banking_notes' => 'Editorial note' }]
      described_class.new(rows: hedged_rows, redirects: {}, dry_run: false).run
      family = Family.find_by(name: 'Amaranthaceae')
      expect(family.storage_physiology).to eq('orthodox')
      expect(family.seed_banking_notes).to eq('Editorial note. Storage detail: onions, garlic, leeks')
    end
  end
end
