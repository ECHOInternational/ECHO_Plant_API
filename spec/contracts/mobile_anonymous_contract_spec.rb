# frozen_string_literal: true

require 'rails_helper'

# Contract: anonymous (unauthenticated) reads that the mobile app performs
# before or without a login. The critical invariant is that public read
# queries return data cleanly and private-scoped queries return empty results
# rather than authentication errors -- the app relies on silent empty
# responses, not 401 errors, when visibility: PRIVATE is requested without
# a token.
RSpec.describe 'Mobile anonymous reads contract', type: :graphql_query do
  # -----------------------------------------------------------------
  # Anonymous plants(visibility: PRIVATE) must return empty nodes,
  # NOT a 401 GraphQL error. The mobile app calls this on startup
  # before login and expects an empty list.
  # -----------------------------------------------------------------
  describe 'plants(visibility: PRIVATE) with no current_user' do
    let!(:public_plant)  { create(:plant, :public) }
    let!(:private_plant) { create(:plant, :private) }

    let(:query) do
      <<~GRAPHQL
        {
          plants(visibility: PRIVATE) {
            nodes {
              id
              primaryCommonName
              scientificName
            }
          }
        }
      GRAPHQL
    end

    it 'returns no top-level GraphQL errors' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      expect(result['errors']).to be_nil
    end

    it 'returns empty nodes (not the private plant)' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      nodes = result.dig('data', 'plants', 'nodes')
      expect(nodes).to be_an(Array)
      expect(nodes).to be_empty
    end
  end

  # -----------------------------------------------------------------
  # Anonymous specimens(visibility: PRIVATE) must also return empty nodes
  # -----------------------------------------------------------------
  describe 'specimens(visibility: PRIVATE) with no current_user' do
    let!(:private_spec) { create(:specimen, :private) }

    let(:query) do
      <<~GRAPHQL
        {
          specimens(visibility: PRIVATE) {
            nodes {
              id
              name
            }
          }
        }
      GRAPHQL
    end

    it 'returns no errors and empty nodes' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'specimens', 'nodes')
      expect(nodes).to be_an(Array)
      expect(nodes).to be_empty
    end
  end

  # -----------------------------------------------------------------
  # Anonymous varieties(visibility: PRIVATE) must return empty nodes
  # -----------------------------------------------------------------
  describe 'varieties(visibility: PRIVATE) with no current_user' do
    let!(:private_variety) { create(:variety, :private) }

    let(:query) do
      <<~GRAPHQL
        {
          varieties(visibility: PRIVATE) {
            nodes {
              id
              name
            }
          }
        }
      GRAPHQL
    end

    it 'returns no errors and empty nodes' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'varieties', 'nodes')
      expect(nodes).to be_an(Array)
      expect(nodes).to be_empty
    end
  end

  # -----------------------------------------------------------------
  # Anonymous locations(visibility: PRIVATE) must return empty nodes
  # -----------------------------------------------------------------
  describe 'locations(visibility: PRIVATE) with no current_user' do
    let!(:private_loc) { create(:location, :private) }

    let(:query) do
      <<~GRAPHQL
        {
          locations(visibility: PRIVATE) {
            nodes {
              id
              name
            }
          }
        }
      GRAPHQL
    end

    it 'returns no errors and empty nodes' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'locations', 'nodes')
      expect(nodes).to be_an(Array)
      expect(nodes).to be_empty
    end
  end

  # -----------------------------------------------------------------
  # Anonymous public plant reads must succeed
  # -----------------------------------------------------------------
  describe 'anonymous public plants read' do
    let!(:public_plant) { create(:plant, :public, scientific_name: 'Musa acuminata') }

    let(:query) do
      pid = PlantApiSchema.id_from_object(public_plant, Plant, {})
      <<~GRAPHQL
        {
          plant(id: "#{pid}", language: "en") {
            id
            primaryCommonName
            scientificName
          }
        }
      GRAPHQL
    end

    it 'returns plant data without authentication' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'plant', 'id')).to be_present
    end
  end

  # -----------------------------------------------------------------
  # Anonymous categories list must succeed (used on the home screen)
  # -----------------------------------------------------------------
  describe 'anonymous categories list' do
    let!(:category) { create(:category, :public) }

    let(:query) do
      <<~GRAPHQL
        {
          categories(first: 15, language: "en", after: "") {
            totalCount
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              name
            }
          }
        }
      GRAPHQL
    end

    it 'returns categories without authentication' do
      result = PlantApiSchema.execute(query, context: { current_user: nil })
      expect(result['errors']).to be_nil
      conn = result.dig('data', 'categories')
      expect(conn['totalCount']).to be >= 1
      expect(conn['nodes']).not_to be_empty
    end
  end
end
