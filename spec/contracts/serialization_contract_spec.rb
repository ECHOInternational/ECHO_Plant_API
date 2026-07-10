# frozen_string_literal: true

require 'rails_helper'

# Contract: scalar serialization formats clients depend on.
# - Visibility enum serializes as the UPPERCASE GraphQL enum name.
# - createdAt serializes as an ISO8601 string equal to record.created_at.iso8601.
# These freeze the wire format so a Rails/graphql-ruby upgrade can't silently
# reshape enum casing or datetime rendering.
RSpec.describe 'Serialization contract', type: :request do
  before :each do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SANDBOX').and_return('true')
    allow(ENV).to receive(:[]).with('SANDBOX_TRUST_LEVEL').and_return('10')
  end

  describe 'visibility enum' do
    # Model visibility value => the exact GraphQL enum name emitted on the wire.
    # (Types::VisibilityEnum also defines a query-only VISIBLE => :visible, which
    # is not a persisted column value, so it isn't a serialization case here.)
    {
      private: 'PRIVATE',
      public: 'PUBLIC',
      draft: 'DRAFT',
      deleted: 'DELETED'
    }.each do |db_value, graphql_value|
      it "serializes #{db_value} as #{graphql_value}" do
        plant = create(:plant, visibility: db_value)
        gid = PlantApiSchema.id_from_object(plant, Plant, {})

        post '/graphql', params: { query: "{ plant(id: \"#{gid}\") { visibility } }" }

        body = JSON.parse(response.body)
        expect(body.dig('data', 'plant', 'visibility')).to eq(graphql_value)
      end
    end
  end

  describe 'datetime' do
    # Observed on Rails 6.0 (default UTC zone): the API emits the "Z" offset
    # form, e.g. "2026-07-10T13:53:27Z", identical to record.created_at.iso8601.
    ISO8601_WITH_OFFSET = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z|\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/.freeze

    it 'serializes createdAt as record.created_at.iso8601' do
      plant = create(:plant, :public)
      gid = PlantApiSchema.id_from_object(plant, Plant, {})

      post '/graphql', params: { query: "{ plant(id: \"#{gid}\") { createdAt } }" }

      created_at = JSON.parse(response.body).dig('data', 'plant', 'createdAt')
      expect(created_at).to eq(plant.created_at.iso8601)
      expect(created_at).to match(ISO8601_WITH_OFFSET)
    end
  end
end
