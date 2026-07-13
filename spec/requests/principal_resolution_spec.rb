# frozen_string_literal: true

require 'rails_helper'

# Request-level spec for principal resolution in sandbox mode.
# Uses the same SANDBOX mechanism as spec/requests/sandbox_mode_spec.rb.
RSpec.describe 'Principal resolution via sandbox', type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return('2')
  end

  # The sandbox user's uid is 'sandbox'; issuer is 'sandbox'.
  let(:sandbox_uid)    { 'sandbox' }
  let(:sandbox_issuer) { 'sandbox' }

  describe 'principal and personal organization provisioning' do
    it 'creates a Principal on first request' do
      expect {
        post '/graphql', params: { query: '{ __typename }' }
      }.to change { Principal.where(identity_issuer: sandbox_issuer, external_uid: sandbox_uid).count }.by(1)
    end

    it 'reuses the same Principal on subsequent requests' do
      post '/graphql', params: { query: '{ __typename }' }
      expect {
        post '/graphql', params: { query: '{ __typename }' }
      }.not_to(change { Principal.count })
    end

    it 'creates a personal Organization for the principal' do
      post '/graphql', params: { query: '{ __typename }' }
      principal = Principal.find_by!(identity_issuer: sandbox_issuer, external_uid: sandbox_uid)
      expect(principal.personal_organization).to be_present
      expect(principal.personal_organization.kind).to eq('personal')
    end

    it 'reuses the same personal Organization on subsequent requests' do
      post '/graphql', params: { query: '{ __typename }' }
      expect {
        post '/graphql', params: { query: '{ __typename }' }
      }.not_to(change { Organization.where(kind: 'personal').count })
    end
  end

  describe 'PaperTrail version metadata', versioning: true do
    # We need a mutation that writes a record. CreatePlant is simplest.
    let(:create_plant_query) do
      <<~GRAPHQL
        mutation($input: CreatePlantInput!) {
          createPlant(input: $input) {
            errors { field message code }
            plant { id }
          }
        }
      GRAPHQL
    end

    # PaperTrail's own set_paper_trail_controller_info before_action fires
    # before require_token; ApplicationController re-registers it after
    # require_token so controller_info carries the resolved principal.
    it 'populates versions.metadata with origin=api and the principal id' do
      post '/graphql',
           params: {
             query: create_plant_query,
             variables: { input: { primaryCommonName: 'Version Test Plant', language: 'en' } }.to_json
           }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['errors']).to be_nil, "GraphQL errors: #{body['errors']}"

      principal = Principal.find_by!(identity_issuer: sandbox_issuer, external_uid: sandbox_uid)
      # Locate the Plant version written by this request.
      version = PaperTrail::Version.where(item_type: 'Plant').order(:created_at).last

      expect(version).to be_present
      expect(version.metadata).to be_a(Hash)
      expect(version.metadata['origin']).to eq('api')
      expect(version.metadata['principal_id']).to eq(principal.id)
    end

    it 'populates versions.metadata with at least origin=api' do
      post '/graphql',
           params: {
             query: create_plant_query,
             variables: { input: { primaryCommonName: 'Origin Test Plant', language: 'en' } }.to_json
           }

      expect(response).to have_http_status(:ok)
      version = PaperTrail::Version.where(item_type: 'Plant').order(:created_at).last
      expect(version).to be_present
      expect(version.metadata).to be_a(Hash)
      expect(version.metadata['origin']).to eq('api')
    end
  end
end
