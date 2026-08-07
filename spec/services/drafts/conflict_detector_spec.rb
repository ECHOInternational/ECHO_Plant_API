# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Drafts::ConflictDetector, :versioning do
  let(:plant) { create(:plant, scientific_name: 'Original', family_names: 'Original family') }

  describe '#conflicted_fields' do
    it 'reports nothing when live has not moved' do
      draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft' },
                                    base_updated_at: plant.updated_at)
      expect(described_class.new(draft).conflicted_fields).to be_empty
    end

    it 'reports a field both the draft and live changed' do
      draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft' },
                                    base_updated_at: plant.updated_at)
      plant.update!(scientific_name: 'Changed under the draft')

      expect(described_class.new(draft).conflicted_fields).to include('scientific_name')
    end

    # The reason for field-level rather than timestamp-level detection. A coarse
    # live.updated_at > base_updated_at check fires on every SourceSynchronizer
    # run touching last_synced_at, which trains editors to click through warnings.
    it 'ignores live changes to fields the draft does not touch' do
      draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft' },
                                    base_updated_at: plant.updated_at)
      plant.update!(family_names: 'Changed elsewhere')

      expect(described_class.new(draft).conflicted_fields).to be_empty
    end
  end

  describe 'RecordDraft#changed_fields' do
    it 'returns the keys from the draft data hash' do
      draft = create(:record_draft, data: { 'a' => 1, 'b' => 2 })
      expect(draft.changed_fields).to match_array(%w[a b])
    end
  end
end
