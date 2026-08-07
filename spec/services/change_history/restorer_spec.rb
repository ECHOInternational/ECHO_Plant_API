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

    it 'skips a blank captured translations value instead of raising' do
      # Regression test for a 500 the history-drawer e2e spec hit end to end:
      # `translations` is `jsonb NOT NULL DEFAULT '{}'`. See the comment on
      # ChangeHistory::Restorer#restorable_attributes for the verified
      # mechanism -- in short, ActiveRecord::Type::Serialized#serialize
      # returns nil (not a dumped `{}`) for any value equal to the column's
      # blank default, so no assignable value can persist an empty jsonb back
      # into this NOT NULL column. This reproduces the failure end to end,
      # not stubbed: clear the plant's only translated field so its
      # translations column genuinely collapses to `{}`, capture that as the
      # restore target, then restore over a later edit. Pre-fix this raised
      # ActiveRecord::NotNullViolation; post-fix it succeeds and -- per the
      # documented silent-partial-restore semantic -- leaves the record's
      # current (re-added) translated content alone rather than reverting it.
      plant = create(:plant)
      Mobility.with_locale(:en) { plant.update!(description: nil) }
      target = PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id).last
      Mobility.with_locale(:en) { plant.update!(description: 'Re-added') }

      result = described_class.new(record: plant, version_id: target.id).call

      expect(result.errors).to be_empty
      expect(Mobility.with_locale(:en) { plant.reload.description }).to eq 'Re-added'
    end

    it 'restores translated values' do
      Mobility.with_locale(:en) { plant.update!(uses: 'First use') }
      target = versions_for(plant).last
      Mobility.with_locale(:en) { plant.update!(uses: 'Second use') }

      described_class.new(record: plant, version_id: target.id).call

      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'First use'
    end

    it 'restores a changed family assignment' do
      old_family = Family.importing { create(:family) }
      new_family = Family.importing { create(:family) }
      plant = create(:plant, family: old_family)
      plant.update!(family: new_family)

      version = versions_for(plant).first

      described_class.new(record: plant, version_id: version.id).call

      expect(plant.reload.family_id).to eq(old_family.id)
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
      other_org = create(:organization, :real)
      other_creator = create(:principal)
      other_owned_by = Faker::Internet.email
      create_version = versions_for(plant).first
      original_owned_by = plant.owned_by

      # Genuinely diverge the live row from the snapshot the restore will
      # reify: if any of these columns were in the write whitelist, the
      # restore would revert them to their create-time values below, and
      # these assertions would catch it. Before this, only `visibility`
      # differed between snapshot and live row, so the ownership/sync
      # assertions passed whether or not the code wrote them.
      plant.update!(
        scientific_name: 'Second',
        visibility: :public,
        owner_organization_id: other_org.id,
        created_by_principal_id: other_creator.id,
        owned_by: other_owned_by
      )
      owner = plant.owner_organization_id
      creator = plant.created_by_principal_id
      owned_by = plant.owned_by
      publication_state = plant.publication_state
      access_level = plant.access_level
      deleted_at = plant.deleted_at

      expect(owner).to eq other_org.id
      expect(creator).to eq other_creator.id
      expect(owned_by).not_to eq original_owned_by

      described_class.new(record: plant, version_id: create_version.id).call
      plant.reload

      expect(plant.scientific_name).to eq 'Original'
      expect(plant.visibility).to eq 'public'
      expect(plant.owner_organization_id).to eq owner
      expect(plant.created_by_principal_id).to eq creator
      expect(plant.owned_by).to eq owned_by
      expect(plant.publication_state).to eq publication_state
      expect(plant.access_level).to eq access_level
      expect(plant.deleted_at).to eq deleted_at
    end

    it 'discards unsaved changes on the caller instance before restoring' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      # Simulate a caller handing over an instance with a pending, unsaved
      # mutation to a disallowed column. @record.update(attributes) would
      # persist this alongside the whitelisted attributes if the service
      # did not reload first.
      plant.visibility = :public

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors).to be_empty
      plant.reload
      expect(plant.visibility).to eq 'private'
      expect(plant.scientific_name).to eq 'Original'
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
