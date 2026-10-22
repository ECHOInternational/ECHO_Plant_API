# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublicationWave do
  let(:data_source) { create(:data_source) }

  def build_wave(**attrs)
    described_class.new({ key: 'fpi-w1', data_source: data_source, selector: 'quality', selection_digest: 'a' * 64,
                          state: 'applying' }.merge(attrs))
  end

  it 'is valid with a key, selector, state and digest' do
    expect(build_wave).to be_valid
  end

  it 'uses a uuid primary key' do
    wave = build_wave.tap(&:save!)
    expect(wave.id).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
  end

  it 'accepts only short lower-case keys of letters, digits and dashes' do
    %w[fpi-w1 abc w-2026-10].each { |key| expect(build_wave(key: key)).to be_valid }
    ['ab', 'FPI-W1', 'fpi_w1', 'fpi w1', 'a' * 41, ''].each { |key| expect(build_wave(key: key)).not_to be_valid }
  end

  it 'keeps keys unique' do
    build_wave.save!
    expect(build_wave).not_to be_valid
    expect { build_wave.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'accepts only known selectors and states' do
    expect(build_wave(selector: 'everything')).not_to be_valid
    expect(build_wave(state: 'done')).not_to be_valid
  end

  # The ledger is visible in public Actions logs and in a public repository's
  # ops tooling, so it must never hold an email address.
  it "refuses notes that contain '@'" do
    expect(build_wave(notes: 'canary of 25 plants')).to be_valid
    wave = build_wave(notes: 'asked by someone@example.org')
    expect(wave).not_to be_valid
    expect(wave.errors[:notes].join).to include("'@'")
  end

  it 'knows which waves are active' do
    applying = build_wave(key: 'w-applying').tap(&:save!)
    applied = build_wave(key: 'w-applied', state: 'applied').tap(&:save!)
    build_wave(key: 'w-gone', state: 'unpublished').save!
    expect(described_class.active).to contain_exactly(applying, applied)
  end

  it 'is versioned (its uuid keeps versions.item_id meaningful)' do
    with_versioning do
      wave = build_wave.tap(&:save!)
      expect(PaperTrail::Version.where(item_type: 'PublicationWave', item_id: wave.id).count).to eq(1)
    end
  end
end

RSpec.describe PublicationWaveItem do
  let(:wave) do
    PublicationWave.create!(key: 'fpi-w1', data_source: create(:data_source), selector: 'quality',
                            selection_digest: 'a' * 64, state: 'applying')
  end

  def build_item(**attrs)
    described_class.new({ publication_wave: wave, item_type: 'Plant', item_id: SecureRandom.uuid,
                          plant_id: SecureRandom.uuid, origin: 'publish', state: 'pending' }.merge(attrs))
  end

  it 'validates its type, origin and state' do
    expect(build_item).to be_valid
    expect(build_item(item_type: 'Variety')).not_to be_valid
    expect(build_item(origin: 'other')).not_to be_valid
    expect(build_item(state: 'other')).not_to be_valid
  end

  it 'holds one row per wave and item' do
    item = build_item.tap(&:save!)
    duplicate = build_item(item_id: item.item_id)
    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  # Like RecordDraft: the items ARE the ledger, so versioning them would only
  # add about 20k version rows per wave.
  it 'writes no PaperTrail versions' do
    with_versioning do
      item = build_item.tap(&:save!)
      item.update!(state: 'applied')
      item.destroy!
      expect(PaperTrail::Version.where(item_type: 'PublicationWaveItem')).not_to exist
    end
  end
end
