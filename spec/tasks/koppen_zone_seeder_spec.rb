# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/koppen_zone_seeder')

RSpec.describe KoppenZoneSeeder do
  def seed(apply: true)
    described_class.new(apply: apply).seed
  end

  it 'seeds all 45 zones across the three levels' do
    result = seed

    expect(result.created).to eq 45
    expect(KoppenZone.groups.count).to eq 5
    expect(KoppenZone.subgroups.count).to eq 8
    expect(KoppenZone.classes.count).to eq 32
  end

  it 'parents every non-group zone' do
    seed

    expect(KoppenZone.where(parent_id: nil).where.not(level: 'group')).to be_empty
    expect(KoppenZone.groups.where.not(parent_id: nil)).to be_empty
  end

  it 'builds the chain Cfa -> Cf -> C' do
    seed

    expect(KoppenZone.find_by(code: 'Cfa').ancestry.map(&:code)).to eq %w[Cf C]
  end

  # A and E have no intermediate level in the classification, so their classes
  # hang directly off the group.
  it 'parents the tropical and polar classes straight to their group' do
    seed

    expect(KoppenZone.find_by(code: 'Aw').parent.code).to eq 'A'
    expect(KoppenZone.find_by(code: 'ET').parent.code).to eq 'E'
  end

  # `authoritative` means "appears in Beck et al. 2018": the 5 groups and the
  # 30 published classes, but not ECHO's 8 intermediates nor the fog variants.
  it 'flags exactly the 35 rows that appear in Beck 2018' do
    seed

    expect(KoppenZone.authoritative.count).to eq 35
    expect(KoppenZone.find_by(code: 'Cf').authoritative).to be false
    expect(KoppenZone.find_by(code: 'Cfa').authoritative).to be true
    expect(KoppenZone.find_by(code: 'BSn').authoritative).to be false
  end

  it 'keeps the two fog variants, parented under their subgroup' do
    seed

    expect(KoppenZone.find_by(code: 'BSn').parent.code).to eq 'BS'
    expect(KoppenZone.find_by(code: 'BWn').parent.code).to eq 'BW'
  end

  it 'corrects the three name errors carried from ECHOcommunity' do
    seed

    names = KoppenZone.where(code: %w[BSn BWn Dsa]).to_h do |z|
      [z.code, Mobility.with_locale(:en) { z.name }]
    end
    expect(names['BSn']).to eq 'Mild Arid Steppe Climate'      # was "Climante"
    expect(names['BWn']).to eq 'Mild Arid Desert Climate'      # was "Clomate"
    expect(names['Dsa']).to eq 'Continental Climate with Hot Dry Summer'
    expect(names['Dsa']).not_to include '  '                   # had a double space
  end

  it 'is idempotent' do
    seed
    result = seed

    expect(result.created).to eq 0
    expect(result.updated).to eq 0
    expect(KoppenZone.count).to eq 45
  end

  # The name lives in the editable translated layer, so a curator's wording
  # must survive a re-seed of the structural columns.
  it 'leaves a curated name alone on re-seed' do
    seed
    zone = KoppenZone.find_by(code: 'Cfa')
    Mobility.with_locale(:en) { zone.update!(name: 'Humid subtropical') }

    seed

    expect(Mobility.with_locale(:en) { zone.reload.name }).to eq 'Humid subtropical'
  end

  it 'writes nothing on a dry run' do
    result = seed(apply: false)

    expect(result.created).to eq 45
    expect(KoppenZone.count).to eq 0
  end
end
