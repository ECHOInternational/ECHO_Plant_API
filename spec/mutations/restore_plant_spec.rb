# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RestorePlant Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: RestorePlantInput!) {
        restorePlant(input: $input) {
          plant {
            id
            visibility
            publicationState
            accessLevel
          }
          errors {
            field
            message
            code
          }
        }
      }
    GRAPHQL
  end

  def execute(plant, user)
    plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: { input: { plantId: plant_id } }
    )
  end

  context 'when anonymous' do
    it 'returns 401' do
      plant = create(:plant, :deleted, owned_by: 'a@b.com', created_by: 'a@b.com')
      result = execute(plant, nil)
      expect(result['data']).to be_nil
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end
  end

  context 'when read-only user' do
    let(:user) { build(:user, :readonly) }

    it 'returns 403' do
      plant = create(:plant, :deleted, owned_by: user.email, created_by: user.email)
      result = execute(plant, user)
      expect(result['data']).to be_nil
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  context 'when write user who owns the record (legacy path)' do
    let(:user) { build(:user, :readwrite) }
    let(:plant) { create(:plant, :deleted, owned_by: user.email, created_by: user.email) }

    it 'restores the plant and returns visibility non-deleted' do
      result = execute(plant, user)
      expect(result['errors']).to be_nil
      payload = result.dig('data', 'restorePlant')
      expect(payload['errors']).to be_empty
      plant.reload
      expect(plant.visibility).not_to eq 'deleted'
      expect(plant.deleted_at).to be_nil
    end

    context 'when plant was public before deletion' do
      let(:plant) do
        p = create(:plant, :public, owned_by: user.email, created_by: user.email)
        p.update(visibility: :deleted)
        p
      end

      it 'restores to public (preserved publication state) not private' do
        result = execute(plant, user)
        expect(result['errors']).to be_nil
        plant.reload
        # The dual-write should recompute visibility from publication_state=published
        # and access_level=public -> visibility PUBLIC
        expect(plant.visibility).to eq 'public'
        payload = result.dig('data', 'restorePlant')
        expect(payload.dig('plant', 'visibility')).to eq 'PUBLIC'
        expect(payload.dig('plant', 'accessLevel')).to eq 'PUBLIC'
      end
    end

    context 'when record is not deleted' do
      let(:plant) { create(:plant, :private, owned_by: user.email, created_by: user.email) }

      it 'returns a 400 payload error' do
        result = execute(plant, user)
        expect(result['errors']).to be_nil
        errors = result.dig('data', 'restorePlant', 'errors')
        expect(errors).not_to be_empty
        expect(errors.first['code']).to eq 400
        expect(errors.first['field']).to eq 'plantId'
      end
    end
  end

  context 'when steward of owning organization' do
    let(:principal) { create(:principal) }
    let(:org) { create(:organization, :real) }
    let(:user) do
      # Use org.id (local UUID) as the claim id -- matching how org_member_actor
      # works in organization_scope_leakage_spec.rb and how OwnedResourcePolicy
      # resolves readable_organization_ids.
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'steward' } }]
      ).tap do |u|
        u.principal = principal
        u.personal_organization = Organization.personal_for!(principal)
      end
    end
    let(:plant) { create(:plant, :deleted, owner_organization_id: org.id, owned_by: 'other@example.com') }

    it 'can restore a plant belonging to their organization' do
      result = execute(plant, user)
      expect(result['errors']).to be_nil
      payload = result.dig('data', 'restorePlant')
      expect(payload['errors']).to be_empty
      plant.reload
      expect(plant.visibility).not_to eq 'deleted'
    end
  end

  context 'when editor (no restore capability)' do
    let(:principal) { create(:principal) }
    let(:org) { create(:organization, :real) }
    let(:user) do
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'editor' } }]
      ).tap do |u|
        u.principal = principal
        u.personal_organization = Organization.personal_for!(principal)
      end
    end
    let(:plant) { create(:plant, :deleted, owner_organization_id: org.id, owned_by: 'other@example.com') }

    it 'returns 403' do
      result = execute(plant, user)
      expect(result['data']).to be_nil
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end
end
