# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'recordHistory query', type: :graphql_query do
  let(:query_string) do
    <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          recordHistory(first: 10) {
            totalCount
            edges {
              node {
                id
                createdAt
                event
                origin
                actorLabel
                subjectType
                subjectLabel
                restorable
                actor { displayName }
                changes { field locale before after }
              }
            }
          }
        }
      }
    GRAPHQL
  end

  def execute(plant, user)
    PlantApiSchema.execute(
      query_string,
      context: { current_user: user },
      variables: { id: PlantApiSchema.id_from_object(plant, Plant, {}) }
    )
  end

  describe 'authorization' do
    it 'returns 401 for anonymous callers', versioning: true do
      plant = create(:plant, :public)
      result = execute(plant, nil)

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end

    it 'returns 403 for an authenticated user who cannot edit', versioning: true do
      plant = create(:plant, :public)
      result = execute(plant, build(:user, :readonly))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  describe 'entries', versioning: true do
    let(:user) { build(:user, :readwrite) }
    let(:plant) { create(:plant, owned_by: user.email, created_by: user.email, scientific_name: 'Before') }

    it 'returns the record entries newest first with actor and diff' do
      PaperTrail.request(
        whodunnit: user.principal.id,
        controller_info: { metadata: { origin: 'api', principal_id: user.principal.id } }
      ) do
        plant.update!(scientific_name: 'After')
      end

      history = execute(plant, user).dig('data', 'plant', 'recordHistory')
      nodes = history['edges'].map { |edge| edge['node'] }

      expect(history['totalCount']).to eq 2
      expect(nodes.first['event']).to eq 'UPDATED'
      expect(nodes.first['origin']).to eq 'API'
      expect(nodes.first['subjectType']).to eq 'RECORD'
      # The :user factory resolves a principal without a display name, so the
      # label falls through to the principal email.
      expect(nodes.first['actorLabel']).to eq user.email
      expect(nodes.first['changes']).to include(
        'field' => 'scientificName', 'locale' => nil, 'before' => 'Before', 'after' => 'After'
      )
      expect(nodes.first['restorable']).to be false
      expect(nodes.last['event']).to eq 'CREATED'
      expect(nodes.last['restorable']).to be true
    end

    it 'includes aggregated child entries' do
      create(:common_name, plant: plant, name: 'Child Entry')

      nodes = execute(plant, user).dig('data', 'plant', 'recordHistory', 'edges').map { |e| e['node'] }
      child = nodes.find { |node| node['subjectType'] == 'COMMON_NAME' }

      expect(child).not_to be_nil
      expect(child['subjectLabel']).to eq 'Child Entry'
      expect(child['event']).to eq 'CREATED'
      expect(child['restorable']).to be false
    end

    it 'gives every entry an opaque id that is not node addressable' do
      node_id = execute(plant, user).dig('data', 'plant', 'recordHistory', 'edges', 0, 'node', 'id')
      type_name, = GraphQL::Schema::UniqueWithinType.decode(node_id)
      expect(type_name).to eq 'ChangeEntry'

      probe = PlantApiSchema.execute(
        'query($id: ID!) { node(id: $id) { id } }',
        context: { current_user: user },
        variables: { id: node_id }
      )
      expect(probe.dig('errors', 0, 'extensions', 'code')).to eq 404
    end
  end
end
