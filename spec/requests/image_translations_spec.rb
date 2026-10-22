# frozen_string_literal: true

require 'rails_helper'

# Image.translations used to be a phantom field: the type delegated to
# Image#translations_array, which did not exist, so any selection raised
# NoMethodError. Run anonymously, as a public client would.
RSpec.describe 'Image translations over HTTP', type: :request do
  let(:plant) { create(:plant, :public) }
  let!(:image) { create(:image, :public, imageable: plant) }
  let(:query) do
    <<~GRAPHQL
      {
        plants(first: 5) {
          nodes {
            images { nodes { translations { locale name description } } }
          }
        }
      }
    GRAPHQL
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return(nil)
    # Off sandbox, require_token builds the verification key even for tokenless
    # requests, and CI/dev carry a placeholder secret that is not a valid key.
    pem_body = OpenSSL::PKey::RSA.generate(2048).public_to_pem.lines[1..-2].join.chomp
    allow(ENV).to receive(:[]).with('APPLICATION_JWT_SECRET').and_return(pem_body)
    # A locale holding only a description is legal for images (name is nullable).
    image.update_columns(translations: {
                           'en' => { 'name' => 'Leaf', 'description' => 'A leaf' },
                           'fr' => { 'description' => 'Une feuille' }
                         })
  end

  it 'resolves the translations field for an anonymous caller' do
    post '/graphql', params: { query: query }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['errors']).to be_nil
    translations = body.dig('data', 'plants', 'nodes', 0, 'images', 'nodes', 0, 'translations')
    expect(translations).to contain_exactly(
      { 'locale' => 'en', 'name' => 'Leaf', 'description' => 'A leaf' },
      { 'locale' => 'fr', 'name' => nil, 'description' => 'Une feuille' }
    )
  end
end
