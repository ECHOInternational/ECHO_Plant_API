# frozen_string_literal: true

require 'rails_helper'

# Contract: Relay connection pagination shape (totalCount, pageInfo, cursors).
# The admin interface pages through plants using exactly these fields; a change
# in totalCount semantics or cursor/endCursor wiring would silently break paging.
RSpec.describe 'Pagination contract', type: :request do
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return('10')
  end

  let(:query) do
    <<-GRAPHQL
      {
        plants(first: 2) {
          totalCount
          pageInfo { hasNextPage endCursor }
          edges { cursor node { id } }
        }
      }
    GRAPHQL
  end

  it 'reports totalCount, page size, hasNextPage and endCursor consistently' do
    create_list(:plant, 3, :public)

    post '/graphql', params: { query: query }

    conn = JSON.parse(response.body).dig('data', 'plants')
    expect(conn['totalCount']).to eq(3)
    expect(conn['edges'].length).to eq(2)
    expect(conn.dig('pageInfo', 'hasNextPage')).to be(true)
    expect(conn.dig('pageInfo', 'endCursor')).to eq(conn['edges'].last['cursor'])
  end
end
