# frozen_string_literal: true

require 'rails_helper'

# Contract: the numeric error code returned in errors[0].extensions.code.
# Clients branch on these codes (redirect to login on 401, show "forbidden"
# on 403, "not found" on 404). The schema centralizes this mapping in
# PlantApiSchema's rescue_from handlers; these specs pin the observed codes.
RSpec.describe 'Error code contract', type: :request do
  def error_code(response)
    JSON.parse(response.body).dig('errors', 0, 'extensions', 'code')
  end

  describe '401 unauthenticated' do
    # The schema maps Pundit::NotAuthorizedError to 401 when context[:current_user]
    # is nil (vs 403 when a user is present). This is executed at the schema level
    # rather than over HTTP: in the test/CI environment the controller runs with
    # SANDBOX=true (every request authenticates as the sandbox user), and with
    # SANDBOX off the placeholder APPLICATION_JWT_SECRET is not a valid RSA key,
    # so require_token raises before any GraphQL 401 mapping can occur. Executing
    # the schema with current_user: nil pins the exact code path that later
    # Rails/graphql-ruby upgrades could break.
    let(:query) do
      <<-GRAPHQL
        mutation($input: CreatePlantInput!) {
          createPlant(input: $input) { plant { id } errors { message } }
        }
      GRAPHQL
    end

    it 'returns 401 for a write mutation with no authenticated user' do
      result = PlantApiSchema.execute(
        query,
        variables: { 'input' => { 'primaryCommonName' => 'X' } },
        context: { current_user: nil }
      )

      expect(result.to_h.dig('errors', 0, 'extensions', 'code')).to eq(401)
    end
  end

  describe '404 not found' do
    before :each do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
      # Super-admin so the policy scope isn't what blocks the lookup.
      allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return('10')
    end

    it 'returns 404 for a validly-encoded id pointing at a nonexistent uuid' do
      missing_id = GraphQL::Schema::UniqueWithinType.encode('Plant', SecureRandom.uuid)

      post '/graphql', params: { query: "{ plant(id: \"#{missing_id}\") { id } }" }

      expect(error_code(response)).to eq(404)
    end

    # graphql-ruby's base64 decoder raises ArgumentError on a malformed id in some
    # versions and wraps it as a bare GraphQL::ExecutionError (no extensions.code)
    # in others; object_from_id rescues both so malformed ids always yield a coded 404.
    # The Relay node field routes through object_from_id; plant(id:) decodes inline.
    it 'returns 404 for a malformed (undecodable) global id via the Relay node field' do
      post '/graphql', params: { query: '{ node(id: "not-base64!!") { id } }' }

      expect(error_code(response)).to eq(404)
      expect(JSON.parse(response.body).dig('errors', 0, 'message')).not_to be_empty
    end
  end

  describe '403 forbidden' do
    before :each do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
      # trust 2 = authenticated write user, but NOT super-admin.
      allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return(nil)
    end

    let(:query) do
      <<-GRAPHQL
        mutation($input: CreateToleranceInput!) {
          createTolerance(input: $input) { tolerance { id } errors { message } }
        }
      GRAPHQL
    end

    # createTolerance requires super-admin (trust > 9). A trust-2 sandbox user is
    # authenticated (current_user present) but unauthorized, so the schema maps
    # Pundit::NotAuthorizedError to 403 (not 401). Observed on Rails 6.0; if the
    # code ever returned 401 here instead, this literal would flag the change.
    it 'returns 403 for a trust-2 user attempting a super-admin lookup mutation' do
      post '/graphql', params: { query: query, variables: { input: { name: 'x' } }.to_json }

      expect(error_code(response)).to eq(403)
    end
  end
end
