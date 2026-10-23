# frozen_string_literal: true

require 'rails_helper'

# API-21 refusals write one structured log line so a production soak can count
# them in CloudWatch Logs Insights. The line carries no query text, variables,
# identity or IP, and the client-facing error responses are unchanged.
RSpec.describe 'API-21 refusal logging', type: :request do
  let(:lines) { [] }
  let(:refusals) { lines.select { |l| l.start_with?('[api21_refusal] ') } }
  let(:payloads) { refusals.map { |l| JSON.parse(l.delete_prefix('[api21_refusal] ')) } }

  before do
    # Anonymous by default, whatever the local .env says.
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return(nil)
    # Off sandbox, require_token builds the verification key even for tokenless
    # requests, and CI/dev carry a placeholder secret that is not a valid key.
    pem_body = OpenSSL::PKey::RSA.generate(2048).public_to_pem.lines[1..-2].join.chomp
    allow(ENV).to receive(:[]).with('APPLICATION_JWT_SECRET').and_return(pem_body)
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
      lines << (args.first || block&.call).to_s
      original.call(*args, &block)
    end
  end

  def gql(query, variables: {}, operation_name: nil, headers: {})
    params = { query: query, variables: variables.to_json }
    params[:operationName] = operation_name if operation_name
    post '/graphql', params: params, headers: headers
    JSON.parse(response.body)
  end

  let(:deep_query) do
    <<~GRAPHQL
      query Deep {
        plants(first: 1) { nodes { categories(first: 1) { nodes { plants(first: 1) { nodes {
          categories(first: 1) { nodes { plants(first: 1) { nodes { categories(first: 1) { nodes { id } } } } } }
        } } } } } }
      }
    GRAPHQL
  end
  let(:complex_query) do
    <<~GRAPHQL
      query Heavy {
        families(first: 100) { nodes { plants(first: 100) { nodes {
          id images { nodes { id baseUrl } } commonNames { nodes { name } }
        } } } }
      }
    GRAPHQL
  end

  it 'logs a page_size refusal with path, value, limit, operation and anonymous flag' do
    body = gql('query Big { plants(first: 501) { nodes { id } } }', operation_name: 'Big',
                                                                    headers: { 'X-Request-Id' => 'req-abc-123' })
    expect(body['errors'].first['message']).to match(/first: 501 exceeds the maximum page size of 500/)
    expect(body['errors'].first['extensions']).to eq('code' => 400)
    expect(payloads.size).to eq(1)
    expect(payloads.first).to include(
      'kind' => 'page_size', 'path' => 'plants', 'argument' => 'first', 'requested' => 501, 'limit' => 500,
      'operation_name' => 'Big', 'authenticated' => false, 'request_id' => 'req-abc-123'
    )
  end

  it 'logs the nested path and last: argument' do
    category = create(:category, :public)
    id = PlantApiSchema.id_from_object(category, Category, {})
    gql('query($id: ID!) { category(id: $id) { plants(last: 900) { nodes { id } } } }',
        variables: { id: id })
    expect(payloads.size).to eq(1)
    expect(payloads.first).to include('kind' => 'page_size', 'argument' => 'last', 'requested' => 900,
                                      'path' => 'category.plants')
  end

  it 'logs a depth refusal' do
    body = gql(deep_query, operation_name: 'Deep')
    expect(body['errors'].first['message']).to match(/exceeds max depth of 12/)
    expect(payloads.size).to eq(1)
    expect(payloads.first).to include('kind' => 'depth', 'limit' => 12, 'operation_name' => 'Deep',
                                      'authenticated' => false)
    expect(payloads.first['requested']).to be > 12
  end

  it 'logs a complexity refusal' do
    body = gql(complex_query)
    expect(body['errors'].first['message']).to match(/exceeds max complexity of 400000/)
    expect(payloads.size).to eq(1)
    expect(payloads.first).to include('kind' => 'complexity', 'limit' => 400_000, 'authenticated' => false)
    expect(payloads.first['requested']).to be > 400_000
  end

  it 'does not log accepted queries' do
    gql('{ plants(first: 500) { nodes { id } } }')
    expect(refusals).to be_empty
  end

  it 'omits operation_name when the client sent none' do
    gql('{ plants(first: 501) { nodes { id } } }')
    expect(payloads.first).to include('operation_name' => nil)
  end

  it 'never logs an operation name that is not a plain GraphQL name' do
    Api21RefusalLogger.log(kind: 'depth', context: { operation_name: "a@b.example\nx", current_user: nil })
    Api21RefusalLogger.log(kind: 'depth', context: { operation_name: 'a' * 101, current_user: nil })
    expect(payloads.map { |p| p['operation_name'] }).to eq([nil, nil])
  end

  context 'with an authenticated caller' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
      allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return(nil)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SANDBOX_ORGS', nil).and_return(nil)
    end

    it 'records authenticated true and no identity, for every kind' do
      gql('{ plants(first: 501) { nodes { id } } }')
      gql(deep_query)
      gql(complex_query)
      expect(payloads.map { |p| p['kind'] }).to eq(%w[page_size depth complexity])
      expect(payloads.map { |p| p['authenticated'] }).to all(be(true))
      refusals.each do |line|
        expect(line).not_to match(/sandbox|@|uid|email|principal|127\.0\.0\.1/i)
      end
      expect(payloads.flat_map(&:keys).uniq).to match_array(
        %w[kind path argument requested limit operation_name authenticated request_id]
      )
    end
  end
end
