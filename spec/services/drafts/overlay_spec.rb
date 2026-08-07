# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Drafts::Overlay do
  let(:plant) { create(:plant, scientific_name: 'Live name', description: 'Live English description') }

  describe '.apply' do
    it 'applies staged values without saving' do
      draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' })

      result = described_class.apply(plant, draft)

      expect(result.scientific_name).to eq('Draft name')
      expect(result).to be_changed
      expect(plant.reload.scientific_name).to eq('Live name')
    end

    it 'returns the same instance rather than a copy' do
      draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' })

      expect(described_class.apply(plant, draft)).to equal(plant)
    end

    it 'ignores keys outside the whitelist' do
      draft = create(:record_draft, draftable: plant,
                                    data: { 'visibility' => 1, 'owned_by' => 'someone@example.com' })
      before_visibility = plant.visibility
      before_owner = plant.owned_by

      described_class.apply(plant, draft)

      expect(plant.visibility).to eq(before_visibility)
      expect(plant.owned_by).to eq(before_owner)
      expect(plant).not_to be_changed
    end

    it 'returns the record untouched when there is no draft' do
      expect(described_class.apply(plant, nil).scientific_name).to eq('Live name')
    end

    it 'leaves an empty draft as a no-op' do
      draft = create(:record_draft, draftable: plant, data: {})

      expect(described_class.apply(plant, draft)).not_to be_changed
    end

    it 'overlays a variety, whose whitelist differs from a plant one' do
      variety = create(:variety, description: 'Live variety description')
      draft = create(:record_draft, draftable: variety,
                                    data: { 'translations' => { 'en' => { 'description' => 'Draft variety description' } } })

      expect(described_class.apply(variety, draft).description).to eq('Draft variety description')
    end
  end

  # The originating use case for the whole feature, and the one place where a
  # naive attribute assignment is not enough: see the comments in
  # Drafts::Overlay for why the container is merged and the Mobility read cache
  # is dropped.
  describe 'translations' do
    let(:draft) do
      create(:record_draft, draftable: plant,
                            data: { 'translations' => { 'sw' => { 'description' => 'Maelezo ya Kiswahili' } } })
    end

    it 'makes the staged locale readable while the live locale stays intact' do
      result = described_class.apply(plant, draft)

      expect(Mobility.with_locale(:sw) { result.description }).to eq('Maelezo ya Kiswahili')
      expect(Mobility.with_locale(:en) { result.description }).to eq('Live English description')
    end

    it 'persists nothing' do
      described_class.apply(plant, draft)

      expect(plant.reload.translations).to eq('en' => { 'description' => 'Live English description' })
    end

    # Mobility's cache plugin memoises a read per locale on the backend
    # instance, and only reload/changes_applied/clear_changes_information drop
    # it. Anything that touched a translated attribute before the overlay --
    # a policy check, a serializer, the conflict detector -- would otherwise
    # pin the pre-draft value for the rest of the request.
    it 'does not serve a translation cached before the overlay' do
      Mobility.with_locale(:sw) { plant.description }

      described_class.apply(plant, draft)

      expect(Mobility.with_locale(:sw) { plant.description }).to eq('Maelezo ya Kiswahili')
    end

    it 'keeps other attributes of a locale the draft only partly stages' do
      plant.update!(translations: { 'sw' => { 'description' => 'Maelezo ya zamani', 'pests_and_diseases' => 'Wadudu' } })

      described_class.apply(plant, draft)

      expect(Mobility.with_locale(:sw) { plant.description }).to eq('Maelezo ya Kiswahili')
      expect(Mobility.with_locale(:sw) { plant.pests_and_diseases }).to eq('Wadudu')
    end

    it 'clears a translation staged as nil' do
      nilled = create(:record_draft, draftable: plant,
                                     data: { 'translations' => { 'en' => { 'description' => nil } } })

      described_class.apply(plant, nilled)

      expect(Mobility.with_locale(:en) { plant.description }).to be_nil
    end

    # A draft row written by hand or by an older version of the code. The
    # overlay must not blow up mid-serialization on it.
    it 'ignores a translations value that is not a hash' do
      broken = create(:record_draft, draftable: plant, data: { 'translations' => 'not a hash' })

      described_class.apply(plant, broken)

      expect(Mobility.with_locale(:en) { plant.description }).to eq('Live English description')
    end

    # The container column is jsonb NOT NULL, and Rails serializes an exactly
    # empty hash to SQL NULL, so an overlay that could produce one would hand
    # the publisher an unsavable record. Merging makes that unreachable.
    it 'never leaves the container empty' do
      emptied = create(:record_draft, draftable: plant, data: { 'translations' => {} })

      described_class.apply(plant, emptied)

      expect(plant.translations).not_to be_empty
    end
  end
end
