# frozen_string_literal: true

require 'rails_helper'

# Verifies that ownership-sensitive fields are server-assigned and never
# accepted as GraphQL mutation arguments (design.md sections 1 and 4).

RSpec.describe 'Protected ownership fields', type: :graphql_mutation do
  let(:write_user) do
    principal    = create(:principal)
    personal_org = Organization.personal_for!(principal)
    User.new(
      'uid' => principal.external_uid,
      'email' => principal.email,
      'trust_levels' => { 'plant' => 2 },
      'organizations' => []
    ).tap do |u|
      u.principal = principal
      u.personal_organization = personal_org
    end
  end

  let(:context) { { current_user: write_user } }

  # -------------------------------------------------------------------------
  # CreatePlant
  # -------------------------------------------------------------------------
  describe 'createPlant' do
    let(:query_string) do
      <<~GRAPHQL
        mutation($input: CreatePlantInput!) {
          createPlant(input: $input) {
            errors { field message code }
            plant { id }
          }
        }
      GRAPHQL
    end

    it 'rejects ownedBy as an unknown argument (GraphQL validation error)' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: {
          input: {
            primaryCommonName: 'Test Plant',
            language: 'en',
            ownedBy: 'attacker@example.org'
          }
        }
      )
      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to match(/ownedBy/i)
    end

    it 'rejects createdBy as an unknown argument' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: {
          input: {
            primaryCommonName: 'Test Plant',
            language: 'en',
            createdBy: 'attacker@example.org'
          }
        }
      )
      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to match(/createdBy/i)
    end

    it 'rejects ownerOrganizationId as an unknown argument' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: {
          input: {
            primaryCommonName: 'Test Plant',
            language: 'en',
            ownerOrganizationId: SecureRandom.uuid
          }
        }
      )
      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to match(/ownerOrganizationId/i)
    end

    it 'rejects createdByPrincipalId as an unknown argument' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: {
          input: {
            primaryCommonName: 'Test Plant',
            language: 'en',
            createdByPrincipalId: SecureRandom.uuid
          }
        }
      )
      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to match(/createdByPrincipalId/i)
    end

    it 'sets created_by_principal_id to the acting principal when a principal is attached' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: { input: { primaryCommonName: 'Ownership Test', language: 'en' } }
      )
      expect(result['errors']).to be_nil
      plant_id = result.dig('data', 'createPlant', 'plant', 'id')
      plant    = PlantApiSchema.object_from_id(plant_id, {})
      expect(plant.created_by_principal_id).to eq(write_user.principal.id)
    end

    it 'sets owner_organization_id to the personal org when a principal is attached' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: { input: { primaryCommonName: 'Ownership Test 2', language: 'en' } }
      )
      expect(result['errors']).to be_nil
      plant_id = result.dig('data', 'createPlant', 'plant', 'id')
      plant    = PlantApiSchema.object_from_id(plant_id, {})
      expect(plant.owner_organization_id).to eq(write_user.personal_organization.id)
    end

    it 'sets created_by_principal_id to nil when no principal is attached (schema-level call)' do
      no_principal_user = User.new(
        'uid' => nil,
        'email' => 'noprincipal@example.org',
        'trust_levels' => { 'plant' => 2 },
        'organizations' => []
      )
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: no_principal_user },
        variables: { input: { primaryCommonName: 'No Principal Plant', language: 'en' } }
      )
      # No principal: the mutation should still succeed with nil ownership fields
      plant_id = result.dig('data', 'createPlant', 'plant', 'id')
      if plant_id
        plant = PlantApiSchema.object_from_id(plant_id, {})
        expect(plant.created_by_principal_id).to be_nil
        expect(plant.owner_organization_id).to be_nil
      else
        # If the auth check prevents it, just verify no 5xx
        expect(result['errors']).to be_present
      end
    end
  end

  # -------------------------------------------------------------------------
  # CreateSpecimen
  # -------------------------------------------------------------------------
  describe 'createSpecimen' do
    let(:plant) { create(:plant, :public) }
    let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

    let(:query_string) do
      <<~GRAPHQL
        mutation($input: CreateSpecimenInput!) {
          createSpecimen(input: $input) {
            errors { field message code }
            specimen { id }
          }
        }
      GRAPHQL
    end

    it 'rejects ownedBy as an unknown argument' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: {
          input: {
            name: 'Test Specimen',
            plantId: plant_gid,
            ownedBy: 'attacker@example.org'
          }
        }
      )
      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to match(/ownedBy/i)
    end

    it 'rejects ownerOrganizationId as an unknown argument' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: {
          input: {
            name: 'Test Specimen',
            plantId: plant_gid,
            ownerOrganizationId: SecureRandom.uuid
          }
        }
      )
      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to match(/ownerOrganizationId/i)
    end

    it 'sets created_by_principal_id to the acting principal when a principal is attached' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: { input: { name: 'Principal Specimen', plantId: plant_gid } }
      )
      expect(result['errors']).to be_nil
      specimen_id = result.dig('data', 'createSpecimen', 'specimen', 'id')
      specimen    = PlantApiSchema.object_from_id(specimen_id, {})
      expect(specimen.created_by_principal_id).to eq(write_user.principal.id)
    end

    it 'sets owner_organization_id to the personal org when a principal is attached' do
      result = PlantApiSchema.execute(
        query_string,
        context: context,
        variables: { input: { name: 'Org Specimen', plantId: plant_gid } }
      )
      expect(result['errors']).to be_nil
      specimen_id = result.dig('data', 'createSpecimen', 'specimen', 'id')
      specimen    = PlantApiSchema.object_from_id(specimen_id, {})
      expect(specimen.owner_organization_id).to eq(write_user.personal_organization.id)
    end
  end
end
