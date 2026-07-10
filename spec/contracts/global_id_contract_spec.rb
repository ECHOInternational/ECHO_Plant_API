# frozen_string_literal: true

require 'rails_helper'

# Contract: the public Relay global-ID format is TypeName + UUID, base64-encoded.
# Clients bookmark and cache these opaque IDs. If the encoding ever changes,
# every previously issued ID breaks. These literals are a tripwire against that.
RSpec.describe 'Global ID contract', type: :request do
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    # Super-admin so policy scope never hides the created plant.
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return('10')
  end

  # A frozen UUID standing in for the exact ID string a client would hold.
  let(:uuid) { '11111111-2222-3333-4444-555555555555' }

  it 'encodes as base64("Plant-<uuid>")' do
    id = GraphQL::Schema::UniqueWithinType.encode('Plant', uuid)

    # Frozen literal: base64 of "Plant-11111111-2222-3333-4444-555555555555".
    # If this ever changes, every bookmarked/cached client Plant ID breaks.
    expect(id).to eq('UGxhbnQtMTExMTExMTEtMjIyMi0zMzMzLTQ0NDQtNTU1NTU1NTU1NTU1')
    expect(id).to eq(Base64.strict_encode64("Plant-#{uuid}"))
  end

  it 'round-trips through decode' do
    id = GraphQL::Schema::UniqueWithinType.encode('Plant', uuid)
    expect(GraphQL::Schema::UniqueWithinType.decode(id)).to eq(['Plant', uuid])
  end

  it 'echoes the same encoded id end-to-end through plant(id:)' do
    plant = create(:plant, :public)
    # Encode with the model class (whose .name == the GraphQL type name "Plant"),
    # matching the id the API actually emits (see sandbox_mode_spec.rb).
    encoded_id = PlantApiSchema.id_from_object(plant, Plant, {})

    post '/graphql', params: { query: "{ plant(id: \"#{encoded_id}\") { id } }" }

    body = JSON.parse(response.body)
    expect(body.dig('data', 'plant', 'id')).to eq(encoded_id)
  end
end
