# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncConflict, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:sync_conflict)).to be_valid
    end

    it 'is not valid without conflict_type' do
      expect(build(:sync_conflict, conflict_type: nil)).not_to be_valid
    end

    it 'is not valid with an invalid conflict_type' do
      expect(build(:sync_conflict, conflict_type: 'bogus')).not_to be_valid
    end

    it 'is not valid without status' do
      expect(build(:sync_conflict, status: nil)).not_to be_valid
    end

    it 'is not valid with an invalid status' do
      expect(build(:sync_conflict, status: 'bogus')).not_to be_valid
    end

    it 'is not valid without a data_source' do
      sc = build(:sync_conflict)
      sc.data_source = nil
      expect(sc).not_to be_valid
    end

    it 'is not valid without a syncable' do
      sc = build(:sync_conflict)
      sc.syncable = nil
      expect(sc).not_to be_valid
    end

    it 'includes all conflict_type values in the constant' do
      expect(SyncConflict::CONFLICT_TYPES).to include('content', 'source_deletion')
    end

    it 'includes all status values in the constant' do
      expect(SyncConflict::STATUSES).to include('open', 'resolved', 'dismissed')
    end
  end

  describe 'associations' do
    it 'belongs to a syncable polymorphic resource' do
      sc = create(:sync_conflict)
      expect(sc.syncable).to be_a(Plant)
    end

    it 'belongs to a data_source' do
      sc = create(:sync_conflict)
      expect(sc.data_source).to be_a(DataSource)
    end

    it 'can optionally belong to a resolved_by_principal' do
      sc = build(:sync_conflict)
      expect(sc.resolved_by_principal).to be_nil
      principal = create(:principal)
      sc.resolved_by_principal = principal
      expect(sc).to be_valid
    end
  end

  describe '.open_conflicts scope' do
    let!(:open)      { create(:sync_conflict, status: 'open') }
    let!(:resolved)  { create(:sync_conflict, :resolved) }
    let!(:dismissed) { create(:sync_conflict, :dismissed) }

    it 'returns only open conflicts' do
      expect(described_class.open_conflicts).to contain_exactly(open)
    end
  end
end
