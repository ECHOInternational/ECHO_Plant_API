# frozen_string_literal: true

require 'rails_helper'

# Helper: build a user who is a member of the given org with a given role.
# Uses local org.id as the claim id (matching org_member_actor pattern in
# organization_scope_leakage_spec.rb).
def org_actor(org, role:, trust: 2)
  principal = create(:principal)
  User.new(
    'uid' => principal.external_uid,
    'email' => principal.email,
    'trust_levels' => { 'plant' => trust },
    'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }]
  ).tap do |u|
    u.principal = principal
    u.personal_organization = Organization.personal_for!(principal)
  end
end

RSpec.describe 'Visibility transition gates on update mutations', type: :graphql_mutation do
  let(:org) { create(:organization, :real) }

  # UpdatePlant: DELETED transition gate
  describe 'UpdatePlant' do
    let(:update_mutation) do
      <<~GRAPHQL
        mutation($input: UpdatePlantInput!) {
          updatePlant(input: $input) {
            plant { id visibility }
            errors { field message code }
          }
        }
      GRAPHQL
    end

    context 'transitioning TO deleted' do
      let(:plant) { create(:plant, :private, owner_organization_id: org.id, owned_by: 'owner@example.com') }

      context 'when org editor (no soft_delete? capability)' do
        let(:user) { org_actor(org, role: 'editor') }

        it 'returns 403 when attempting to set visibility DELETED' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          result = PlantApiSchema.execute(
            update_mutation,
            context: { current_user: user },
            variables: { input: { plantId: plant_id, visibility: 'DELETED' } }
          )
          expect(result['data']).to be_nil
          expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
        end
      end

      context 'when org steward (has soft_delete? capability)' do
        let(:user) { org_actor(org, role: 'steward') }

        it 'allows transitioning to deleted' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          result = PlantApiSchema.execute(
            update_mutation,
            context: { current_user: user },
            variables: { input: { plantId: plant_id, visibility: 'DELETED' } }
          )
          expect(result['errors']).to be_nil
          plant.reload
          expect(plant.visibility_deleted?).to be true
        end
      end

      context 'when owner (readwrite, legacy_manage?)' do
        let(:user) { build(:user, :readwrite) }
        let(:plant) { create(:plant, :private, owned_by: user.email, owner_organization_id: org.id) }

        it 'allows owner to soft-delete via visibility DELETED (legacy contract)' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          result = PlantApiSchema.execute(
            update_mutation,
            context: { current_user: user },
            variables: { input: { plantId: plant_id, visibility: 'DELETED' } }
          )
          expect(result['errors']).to be_nil
          plant.reload
          expect(plant.visibility_deleted?).to be true
        end
      end
    end

    context 'transitioning FROM deleted (restore via visibility)' do
      let(:plant) do
        create(:plant, :deleted, owner_organization_id: org.id, owned_by: 'owner@example.com')
      end

      context 'when org editor (no restore? capability)' do
        let(:user) { org_actor(org, role: 'editor') }

        it 'returns 403 when attempting to restore via visibility PRIVATE' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          result = PlantApiSchema.execute(
            update_mutation,
            context: { current_user: user },
            variables: { input: { plantId: plant_id, visibility: 'PRIVATE' } }
          )
          expect(result['data']).to be_nil
          expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
        end
      end

      context 'when org steward (has restore? capability)' do
        let(:user) { org_actor(org, role: 'steward') }

        it 'allows restoring via visibility PRIVATE' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          result = PlantApiSchema.execute(
            update_mutation,
            context: { current_user: user },
            variables: { input: { plantId: plant_id, visibility: 'PRIVATE' } }
          )
          expect(result['errors']).to be_nil
          plant.reload
          expect(plant.visibility).not_to eq 'deleted'
        end
      end
    end

    # Confirm mobile contract still works: trust-2 owner deletes via updateSpecimen
    describe 'UpdateSpecimen (mobile delete contract)' do
      let(:owner_user) { build(:user, :readwrite) }
      let(:specimen) { create(:specimen, owned_by: owner_user.email, created_by: owner_user.email) }

      let(:update_specimen_mutation) do
        <<~GRAPHQL
          mutation($input: UpdateSpecimenInput!) {
            updateSpecimen(input: $input) {
              specimen { id visibility }
            }
          }
        GRAPHQL
      end

      it 'trust-2 owner can delete their specimen via visibility DELETED (frozen mobile contract)' do
        spec_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
        result = PlantApiSchema.execute(
          update_specimen_mutation,
          context: { current_user: owner_user },
          variables: { input: { specimenId: spec_id, visibility: 'DELETED' } }
        )
        expect(result['errors']).to be_nil
        expect(result.dig('data', 'updateSpecimen', 'specimen', 'visibility')).to eq 'DELETED'
        expect(Specimen.find(specimen.id).visibility_deleted?).to be true
      end
    end
  end

  # publicationState and accessLevel args on UpdatePlant
  describe 'UpdatePlant publicationState/accessLevel args' do
    let(:owner_user) { build(:user, :readwrite) }
    let(:plant) { create(:plant, :private, owned_by: owner_user.email) }

    let(:update_mutation) do
      <<~GRAPHQL
        mutation($input: UpdatePlantInput!) {
          updatePlant(input: $input) {
            plant { publicationState accessLevel }
            errors { field message code }
          }
        }
      GRAPHQL
    end

    it 'sets publicationState to DRAFT' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        update_mutation,
        context: { current_user: owner_user },
        variables: { input: { plantId: plant_id, publicationState: 'DRAFT' } }
      )
      expect(result['errors']).to be_nil
      plant.reload
      expect(plant.publication_draft?).to be true
      expect(result.dig('data', 'updatePlant', 'plant', 'publicationState')).to eq 'DRAFT'
    end

    it 'sets accessLevel to PUBLIC' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        update_mutation,
        context: { current_user: owner_user },
        variables: { input: { plantId: plant_id, accessLevel: 'PUBLIC' } }
      )
      expect(result['errors']).to be_nil
      plant.reload
      expect(plant.access_public?).to be true
    end

    context 'when plant is deleted' do
      let(:plant) { create(:plant, :deleted, owned_by: owner_user.email) }

      it 'changing publicationState does not undelete the record' do
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(
          update_mutation,
          context: { current_user: owner_user },
          variables: { input: { plantId: plant_id, publicationState: 'PUBLISHED' } }
        )
        expect(result['errors']).to be_nil
        plant.reload
        # deleted_at should NOT be cleared by publicationState change alone
        expect(plant.deleted_at).not_to be_nil
      end
    end
  end
end
