# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyRefresh, type: :service do
  before do
    Family.importing do
      create(:family, name: 'Malvaceae', col_id: 'CDB')
      create(:family, name: 'Tiliaceae', col_id: 'H9G')
    end
  end

  def upstream(*names)
    names.map { |n| { name: n, col_id: "X#{n}", kingdom: 'Plantae', plant_type: 'Angiosperms' } }
  end

  it 'reports a family that is new upstream' do
    diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
    expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
  end

  it 'reports a family that has vanished upstream' do
    diff = described_class.new(upstream('Malvaceae')).diff
    expect(diff[:vanished].map(&:name)).to eq(['Tiliaceae'])
  end

  it 'counts the plants affected by a vanished family' do
    tiliaceae = Family.find_by(name: 'Tiliaceae')
    create(:plant, family: tiliaceae)
    diff = described_class.new(upstream('Malvaceae')).diff
    expect(diff[:affected_plant_counts]['Tiliaceae']).to eq(1)
  end

  it 'applies nothing during a diff' do
    described_class.new(upstream('Malvaceae')).diff
    expect(Family.find_by(name: 'Tiliaceae')).to be_present
    expect(Family.find_by(name: 'Tiliaceae').status).to eq('accepted')
  end

  # The col_id hazard carried forward from Task 9's review: families.col_id
  # has its own unique partial index, separate from the lower(name) index
  # this diff matches on. A newer COL release can hand a "new" family name a
  # col_id that some existing local row already holds (an id migrating off
  # the row it used to belong to), which would otherwise abort the whole
  # Family.importing transaction with a hard uniqueness violation.
  describe 'the col_id collision hazard' do
    it 'reports rather than proposes writing a family whose col_id is already taken locally' do
      rows = upstream('Malvaceae', 'Tiliaceae') + [
        { name: 'Brassicaceae', col_id: 'CDB', kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]

      diff = described_class.new(rows).diff

      expect(diff[:added]).to be_empty
      expect(diff[:col_id_conflicts].map { |r| r[:name] }).to eq(['Brassicaceae'])
    end

    it 'reports only the first of two new families that arrive sharing one col_id' do
      rows = upstream('Malvaceae', 'Tiliaceae') + [
        { name: 'Brassicaceae', col_id: 'NEWID', kingdom: 'Plantae', plant_type: 'Angiosperms' },
        { name: 'Rosaceae', col_id: 'NEWID', kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]

      diff = described_class.new(rows).diff

      expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
      expect(diff[:col_id_conflicts].map { |r| r[:name] }).to eq(['Rosaceae'])
    end

    it 'does not treat a blank col_id as a conflict' do
      rows = upstream('Malvaceae', 'Tiliaceae') + [
        { name: 'Brassicaceae', col_id: nil, kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]

      diff = described_class.new(rows).diff

      expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
      expect(diff[:col_id_conflicts]).to be_empty
    end
  end

  describe '#apply_merge' do
    it 'repoints plants and supersedes the old family' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      malvaceae = Family.find_by(name: 'Malvaceae')
      plant = create(:plant, family: tiliaceae)

      described_class.new([]).apply_merge(tiliaceae, malvaceae)

      expect(plant.reload.family).to eq(malvaceae)
      expect(tiliaceae.reload.status).to eq('superseded')
      expect(tiliaceae.superseded_by).to eq(malvaceae)
    end

    it 'keeps the superseded row so nothing dangles' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      described_class.new([]).apply_merge(tiliaceae, Family.find_by(name: 'Malvaceae'))
      expect(Family.find_by(name: 'Tiliaceae')).to be_present
    end
  end

  describe '#apply_additions!' do
    it 'writes the added rows as accepted families' do
      diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
      count = described_class.new([]).apply_additions!(diff[:added], version: 'COL26.7 XR',
                                                                     snapshot_date: Date.new(2026, 7, 17))

      expect(count).to eq(1)
      expect(Family.find_by(name: 'Brassicaceae')).to be_present
    end

    it 'leaves translations as an empty hash rather than NULL' do
      # Mirrors the exact regression FamilySeeder guards against: an explicit
      # translations: {} in the merged row collapses to a literal SQL NULL
      # under upsert_all and raises ActiveRecord::NotNullViolation, so the
      # key must be omitted and left to the column default instead.
      diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
      described_class.new([]).apply_additions!(diff[:added], version: 'COL26.7 XR',
                                                             snapshot_date: Date.new(2026, 7, 17))

      expect(Family.find_by(name: 'Brassicaceae').translations).to eq({})
    end

    it 'does nothing for an empty list' do
      expect(described_class.new([]).apply_additions!([])).to eq(0)
    end

    # Belt-and-suspenders regression for the col_id hazard: even if a caller
    # bypasses #diff's own filtering and hands apply_additions! a row whose
    # col_id collides with an existing family, the failure must be a clear,
    # rescued error -- never a raw, unexplained PG::UniqueViolation bubbling
    # out of the middle of the Family.importing transaction.
    it 'raises a clear error rather than an unexplained crash if a col_id collision reaches the write' do
      colliding_row = { name: 'Brassicaceae', col_id: 'CDB', kingdom: 'Plantae', plant_type: 'Angiosperms' }

      expect do
        described_class.new([]).apply_additions!([colliding_row], version: 'COL26.7 XR',
                                                                  snapshot_date: Date.new(2026, 7, 17))
      end.to raise_error(FamilyRefresh::ColIdCollisionError, /CDB/)
    end
  end

  describe FamilyRefresh::Report do
    it 'renders the vanished families and any col_id conflicts for a human to review' do
      rows = upstream('Malvaceae') + [
        { name: 'Brassicaceae', col_id: 'CDB', kingdom: 'Plantae', plant_type: 'Angiosperms' }
      ]
      diff = FamilyRefresh.new(rows).diff

      text = described_class.new(diff).to_s

      expect(text).to include('Tiliaceae')
      expect(text).to include('Brassicaceae')
      expect(text).to include('col_id')
    end
  end
end
