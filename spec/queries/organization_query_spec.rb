# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Organization Query', type: :graphql_query do
  let(:query_string) do
    <<~GRAPHQL
      query($id: ID!) {
        organization(id: $id) {
          id
          name
          kind
        }
      }
    GRAPHQL
  end

  def execute(user, id)
    PlantApiSchema.execute(query_string, context: { current_user: user }, variables: { id: id })
  end

  let(:current_user) { build(:user) }
  let(:org) { create(:organization, :real) }
  let(:global_id) { GraphQL::Schema::UniqueWithinType.encode('Organization', org.id) }

  context 'when anonymous (no current_user)' do
    it 'returns a 401 error and no data' do
      result = execute(nil, global_id)
      expect(result.dig('data', 'organization')).to be_nil
      expect(result['errors']).not_to be_empty
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end
  end

  context 'when authenticated' do
    it 'returns the organization by its Relay global id' do
      result = execute(current_user, global_id)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'organization', 'id')).to eq global_id
      expect(result.dig('data', 'organization', 'name')).to eq org.name
      expect(result.dig('data', 'organization', 'kind')).to eq 'real'
    end

    it 'returns a 404 error for an unknown organization id' do
      unknown = GraphQL::Schema::UniqueWithinType.encode('Organization', SecureRandom.uuid)
      result = execute(current_user, unknown)
      expect(result.dig('data', 'organization')).to be_nil
      expect(result['errors']).not_to be_empty
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 404
    end
  end
end
