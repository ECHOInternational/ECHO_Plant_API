# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sandbox mode', type: :request do
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
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
end
