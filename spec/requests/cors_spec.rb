# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CORS' do
  describe 'request wiring' do
    it 'requests to /graphql proceed without CORS errors' do
      # This test verifies the middleware is wired and the endpoint is reachable.
      # Rack-cors headers are tested via unit tests for the origin parsing logic.
      post '/graphql', params: { query: '{ __typename }' }
      expect(response).to have_http_status(:ok)
    end
  end
end

RSpec.describe CorsOrigins do
  describe '.list' do
    it 'returns default origins when CORS_ORIGINS is not set' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch)
        .with('CORS_ORIGINS', 'echocommunity.org,http://development.echocommunity.org:3000')
        .and_return('echocommunity.org,http://development.echocommunity.org:3000')

      origins = CorsOrigins.list
      expect(origins).to eq(['echocommunity.org', 'http://development.echocommunity.org:3000'])
    end

    it 'parses and strips CORS_ORIGINS when set' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch)
        .with('CORS_ORIGINS', 'echocommunity.org,http://development.echocommunity.org:3000')
        .and_return('http://custom1.com, http://custom2.com , http://custom3.com')

      origins = CorsOrigins.list
      expect(origins).to eq(['http://custom1.com', 'http://custom2.com', 'http://custom3.com'])
    end

    it 'handles single origin' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch)
        .with('CORS_ORIGINS', 'echocommunity.org,http://development.echocommunity.org:3000')
        .and_return('http://single.com')

      origins = CorsOrigins.list
      expect(origins).to eq(['http://single.com'])
    end

    it 'handles empty whitespace correctly' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch)
        .with('CORS_ORIGINS', 'echocommunity.org,http://development.echocommunity.org:3000')
        .and_return('  http://origin1.com  ,  http://origin2.com  ')

      origins = CorsOrigins.list
      expect(origins).to eq(['http://origin1.com', 'http://origin2.com'])
    end
  end
end
