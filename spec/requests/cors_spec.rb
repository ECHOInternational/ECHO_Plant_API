# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CORS', type: :request do
  # Use sandbox mode for consistent authentication across tests
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return(nil)
  end

  describe 'allowed origins' do
    it 'includes Access-Control-Allow-Origin header for echocommunity.org origin (https scheme)' do
      get '/health', headers: { 'Origin' => 'https://echocommunity.org' }
      expect(response).to have_http_status(:ok)
      # Rack-cors echoes back the requesting origin when it matches the bare domain (scheme-agnostic)
      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://echocommunity.org')
    end

    it 'includes Access-Control-Allow-Origin header for echocommunity.org origin (http scheme)' do
      get '/health', headers: { 'Origin' => 'http://echocommunity.org' }
      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to eq('http://echocommunity.org')
    end

    it 'includes Access-Control-Allow-Origin header for development origin' do
      get '/health', headers: { 'Origin' => 'http://development.echocommunity.org:3000' }
      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to eq('http://development.echocommunity.org:3000')
    end

    it 'works with POST /graphql for allowed origin' do
      post '/graphql',
           params: { query: '{ __typename }' },
           headers: { 'Origin' => 'https://echocommunity.org' }
      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://echocommunity.org')
    end
  end

  describe 'disallowed origins' do
    it 'omits Access-Control-Allow-Origin header for unauthorized origin' do
      get '/health', headers: { 'Origin' => 'https://evil.example.com' }
      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'omits Access-Control-Allow-Origin for POST /graphql with unauthorized origin' do
      post '/graphql',
           params: { query: '{ __typename }' },
           headers: { 'Origin' => 'https://attacker.example.com' }
      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end
  end

  describe 'multiple requests from same origin' do
    it 'sends CORS headers consistently across requests' do
      get '/health', headers: { 'Origin' => 'https://echocommunity.org' }
      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://echocommunity.org')

      post '/graphql',
           params: { query: '{ __typename }' },
           headers: { 'Origin' => 'https://echocommunity.org' }
      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://echocommunity.org')
    end

    it 'consistently denies CORS headers for unauthorized origins' do
      get '/health', headers: { 'Origin' => 'https://evil.example.com' }
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil

      post '/graphql',
           params: { query: '{ __typename }' },
           headers: { 'Origin' => 'https://evil.example.com' }
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
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
