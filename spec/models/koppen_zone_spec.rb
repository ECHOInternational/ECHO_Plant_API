# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KoppenZone do
  def build_zone(code:, level: 'class', **rest)
    KoppenZone.new(code: code, level: level,
                   classification_source: 'test', classification_version: 'v1',
                   snapshot_date: Date.new(2018, 10, 30), **rest)
  end

  def create_zone(**args)
    described_class.importing { build_zone(**args).tap(&:save!) }
  end

  describe 'the locked list' do
    it 'refuses to create a zone outside an import' do
      expect { build_zone(code: 'Zz').save! }
        .to raise_error(KoppenZone::ImmutableListError, /locked reference list/)
    end

    it 'refuses to destroy a zone outside an import' do
      zone = create_zone(code: 'Zz')

      expect { zone.destroy! }.to raise_error(KoppenZone::ImmutableListError)
      expect(described_class.exists?(zone.id)).to be true
    end

    it 'allows both inside an import' do
      zone = create_zone(code: 'Zz')
      expect(zone).to be_persisted

      described_class.importing { zone.destroy! }
      expect(described_class.exists?(zone.id)).to be false
    end

    # The model callback alone is bypassed by insert_all, delete_all and a
    # console session, which is the whole reason the trigger exists.
    it 'is enforced by the database, not just the model' do
      expect {
        described_class.insert_all([{ code: 'Yy', level: 'class',
                                      classification_source: 't',
                                      classification_version: 'v1',
                                      snapshot_date: Date.new(2018, 10, 30),
                                      created_at: Time.current,
                                      updated_at: Time.current }])
      }
        .to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end

    it 'relocks after an import, even when one raised' do
      expect do
        described_class.importing { raise 'boom' }
      end.to raise_error('boom')

      expect { build_zone(code: 'Xx').save! }
        .to raise_error(KoppenZone::ImmutableListError)
    end
  end

  describe 'validation' do
    it 'rejects a level outside the three' do
      zone = build_zone(code: 'Qq', level: 'kingdom')
      expect(zone).not_to be_valid
      expect(zone.errors[:level]).to be_present
    end

    it 'requires the provenance columns' do
      zone = KoppenZone.new(code: 'Qq', level: 'class')
      expect(zone).not_to be_valid
      expect(zone.errors.attribute_names)
        .to include(:classification_source, :classification_version, :snapshot_date)
    end

    it 'refuses to be its own parent' do
      zone = create_zone(code: 'Zz')
      zone.parent_id = zone.id
      expect(zone).not_to be_valid
    end
  end

  describe 'the hierarchy' do
    it 'walks up to the group, nearest first' do
      group = create_zone(code: 'C', level: 'group')
      sub = create_zone(code: 'Cf', level: 'subgroup', parent: group)
      leaf = create_zone(code: 'Cfa', level: 'class', parent: sub)

      expect(leaf.ancestry.map(&:code)).to eq %w[Cf C]
      expect(group.ancestry).to be_empty
    end

    it 'will not let a parent be destroyed out from under its children' do
      group = create_zone(code: 'C', level: 'group')
      create_zone(code: 'Cf', level: 'subgroup', parent: group)

      described_class.importing { expect(group.destroy).to be false }
      expect(described_class.exists?(group.id)).to be true
    end
  end

  it 'keeps the translated name in the editable layer' do
    zone = create_zone(code: 'Cfa')
    Mobility.with_locale(:en) { zone.update!(name: 'Humid subtropical') }

    expect(Mobility.with_locale(:en) { zone.reload.name }).to eq 'Humid subtropical'
    expect(zone.translations_array.first[:locale]).to eq 'en'
  end
end
