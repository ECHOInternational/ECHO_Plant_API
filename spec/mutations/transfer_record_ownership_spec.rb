# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TransferRecordOwnership Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: TransferRecordOwnershipInput!) {
        transferRecordOwnership(input: $input) {
          record {
            ... on Plant { id ownerOrganization { id } }
            ... on Variety { id ownerOrganization { id } }
          }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  let(:target_org) { create(:organization, :real) }
  let(:plant) { create(:plant, :private, owned_by: 'owner@example.com') }

  def execute(record, to_org, user)
    record_id = PlantApiSchema.id_from_object(record, record.class, {})
    org_id = PlantApiSchema.id_from_object(to_org, Organization, {})
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: { input: { recordId: record_id, toOrganizationId: org_id } }
    )
  end

  context 'when system superuser (trust >= 10)' do
    let(:user) { build(:user, :superadmin) }

    it 'transfers plant ownership and returns the updated record' do
      result = execute(plant, target_org, user)
      expect(result['errors']).to be_nil
      payload = result.dig('data', 'transferRecordOwnership')
      expect(payload['errors']).to be_empty
      plant.reload
      expect(plant.owner_organization_id).to eq target_org.id
    end

    it 'does not change source_organization_id' do
      original_source = plant.source_organization_id
      execute(plant, target_org, user)
      plant.reload
      expect(plant.source_organization_id).to eq original_source
    end

    it 'does not change owned_by (legacy column)' do
      execute(plant, target_org, user)
      plant.reload
      expect(plant.owned_by).to eq 'owner@example.com'
    end

    context 'with a Variety record' do
      let(:variety) { create(:variety, :private, owned_by: 'owner@example.com') }

      it 'transfers variety ownership' do
        result = execute(variety, target_org, user)
        expect(result['errors']).to be_nil
        payload = result.dig('data', 'transferRecordOwnership')
        expect(payload['errors']).to be_empty
        variety.reload
        expect(variety.owner_organization_id).to eq target_org.id
      end
    end
  end

  context 'when trust-9 admin (not system superuser)' do
    let(:user) { build(:user, :admin) }

    it 'returns 403' do
      result = execute(plant, target_org, user)
      expect(result['data']).to be_nil
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  context 'when normal readwrite user' do
    let(:user) { build(:user, :readwrite) }

    it 'returns 403' do
      result = execute(plant, target_org, user)
      expect(result['data']).to be_nil
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  context 'when anonymous' do
    it 'returns 401' do
      result = execute(plant, target_org, nil)
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end
  end
end
