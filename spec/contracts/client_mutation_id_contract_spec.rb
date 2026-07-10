# frozen_string_literal: true

require 'rails_helper'

# Contract: Relay's clientMutationId is echoed back verbatim in the mutation
# payload. Relay clients rely on this to correlate optimistic updates with
# responses; if it stopped round-tripping, mutation reconciliation would break.
RSpec.describe 'clientMutationId contract', type: :request do
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return(nil) # trust 2 = write
  end

  let(:query) do
    <<-GRAPHQL
      mutation($input: CreatePlantInput!) {
        createPlant(input: $input) {
          clientMutationId
          plant { id }
          errors { message }
        }
      }
    GRAPHQL
  end

  it 'echoes the supplied clientMutationId verbatim' do
    variables = {
      input: {
        clientMutationId: 'contract-spec-123',
        primaryCommonName: 'Contract Spec Plant'
      }
    }

    post '/graphql', params: { query: query, variables: variables.to_json }

    body = JSON.parse(response.body)
    expect(body.dig('data', 'createPlant', 'clientMutationId')).to eq('contract-spec-123')
  end
end
