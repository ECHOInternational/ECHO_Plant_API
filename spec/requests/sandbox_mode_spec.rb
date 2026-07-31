# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sandbox mode', type: :request do
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return(nil)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SANDBOX_ORGS', nil).and_return(nil)
  end

  it 'authenticates tokenless requests as the sandbox user' do
    post '/graphql', params: { query: '{ __typename }' }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['data']).to eq('__typename' => 'Query')
  end

  describe 'SANDBOX_TRUST_LEVEL' do
    let(:other_owner_category) { create(:category, visibility: :public, owned_by: 'someone@example.com') }
    let(:delete_query) do
      <<-GRAPHQL
        mutation($input: DeleteCategoryInput!) {
          deleteCategory(input: $input) { categoryId errors { message } }
        }
      GRAPHQL
    end
    let(:category_gid) { PlantApiSchema.id_from_object(other_owner_category, Category, {}) }

    it 'defaults to read/write (trust level 2)' do
      post '/graphql', params: { query: delete_query, variables: { input: { categoryId: category_gid } }.to_json }
      body = JSON.parse(response.body)
      expect(body['errors'][0]['extensions']['code']).to eq 403
    end

    it 'grants the configured trust level' do
      allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return('10')
      post '/graphql', params: { query: delete_query, variables: { input: { categoryId: category_gid } }.to_json }
      body = JSON.parse(response.body)
      expect(body['errors']).to be_nil
      expect(body['data']['deleteCategory']['categoryId']).to eq category_gid
    end
  end

  describe 'SANDBOX_ORGS' do
    let(:me_query) { '{ me { organizations { role organization { name kind } } } }' }

    def me_organizations
      post '/graphql', params: { query: me_query }
      JSON.parse(response.body).dig('data', 'me', 'organizations')
    end

    it 'gives the sandbox user only its personal organization by default' do
      expect(me_organizations.map { |m| m.dig('organization', 'kind') }).to eq ['personal']
    end

    it 'adds the configured organizations, creating the mirror rows on demand' do
      allow(ENV).to receive(:fetch).with('SANDBOX_ORGS', nil)
                                   .and_return('ECHO Asia:editor,ECHO North America')

      memberships = me_organizations
      real = memberships.reject { |m| m.dig('organization', 'kind') == 'personal' }
      expect(real.map { |m| m.dig('organization', 'name') }).to contain_exactly('ECHO Asia', 'ECHO North America')
      expect(real.map { |m| m['role'] }).to contain_exactly('editor', 'org_admin')
      expect(Organization.where(kind: 'real').pluck(:name))
        .to contain_exactly('ECHO Asia', 'ECHO North America')
    end

    it 'reuses the same organization row across requests' do
      allow(ENV).to receive(:fetch).with('SANDBOX_ORGS', nil).and_return('ECHO Asia:editor')
      2.times { me_organizations }
      expect(Organization.where(kind: 'real', name: 'ECHO Asia').count).to eq 1
    end
  end
end
