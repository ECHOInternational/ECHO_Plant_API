# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::Restorer, versioning: true do
  def versions_for(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id)
  end

  describe 'a plant restore' do
    let(:plant) { create(:plant, scientific_name: 'Original', has_edible_green_leaves: false) }

    it 'restores the state immediately after the chosen entry' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')
      plant.update!(scientific_name: 'Third')

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors).to be_empty
      expect(plant.reload.scientific_name).to eq 'Original'
    end

    it 'restores translated values' do
      Mobility.with_locale(:en) { plant.update!(uses: 'First use') }
      target = versions_for(plant).last
      Mobility.with_locale(:en) { plant.update!(uses: 'Second use') }

      described_class.new(record: plant, version_id: target.id).call

      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'First use'
    end

    it 'records the restore as a new version stamped with the source version' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      expect { described_class.new(record: plant, version_id: create_version.id).call }
        .to change { versions_for(plant).count }.by(1)

      expect(versions_for(plant).last.metadata['restored_from_version_id']).to eq create_version.id
    end

    it 'keeps the controller provenance metadata on the restore version' do
      principal = create(:principal)
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      PaperTrail.request(controller_info: { metadata: { origin: 'api', principal_id: principal.id } }) do
        described_class.new(record: plant, version_id: create_version.id).call
      end

      metadata = versions_for(plant).last.metadata
      expect(metadata['origin']).to eq 'api'
      expect(metadata['principal_id']).to eq principal.id
      expect(metadata['restored_from_version_id']).to eq create_version.id
    end

    it 'never touches ownership, visibility or sync columns' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second', visibility: :public)
      owner = plant.owner_organization_id
      creator = plant.created_by_principal_id

      described_class.new(record: plant, version_id: create_version.id).call
      plant.reload

      expect(plant.visibility).to eq 'public'
      expect(plant.owner_organization_id).to eq owner
      expect(plant.created_by_principal_id).to eq creator
      expect(plant.owned_by).to be_present
    end

    it 'refuses the newest entry' do
      plant.update!(scientific_name: 'Second')
      newest = versions_for(plant).last

      result = described_class.new(record: plant, version_id: newest.id).call

      expect(result.errors.first).to include(field: 'versionId', code: 400)
      expect(result.errors.first[:message]).to match(/already the current state/i)
    end

    it 'refuses a soft-deleted record' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')
      plant.update!(visibility: :deleted)

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors.first).to include(field: 'versionId', code: 400)
      expect(result.errors.first[:message]).to match(/trash/i)
    end

    it 'refuses a version that belongs to another record' do
      other = create(:plant)
      other.update!(scientific_name: 'Elsewhere')
      foreign = versions_for(other).last

      result = described_class.new(record: plant, version_id: foreign.id).call

      expect(result.errors.first).to include(field: 'versionId', code: 404)
    end

    it 'leaves validation failures on the record' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')
      allow(plant).to receive(:update) do
        plant.errors.add(:scientific_name, 'is invalid')
        false
      end

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors).to be_empty
      expect(plant.errors).not_to be_empty
    end
  end

  describe 'a variety restore' do
    let(:variety) { create(:variety, has_edible_mature_fruit: false) }

    it 'restores editable content attributes' do
      create_version = versions_for(variety).first
      variety.update!(has_edible_mature_fruit: true)

      described_class.new(record: variety, version_id: create_version.id).call

      expect(variety.reload.has_edible_mature_fruit).to be false
    end
  end
end
