# frozen_string_literal: true

require 'rails_helper'

# Contract: read-only GraphQL operations used by the frozen React Native
# mobile app (echocommunity-app). Any server change that removes or renames
# a field the app relies on will make one of these specs fail.
#
# Source documents extracted verbatim from:
#   app/store/Plants/action.js
#   app/store/SeedTrialReports/action.js
#
# The app interpolates language/cursor values into the query string; those
# are substituted with realistic values here.
RSpec.describe 'Mobile reads contract', type: :graphql_query do
  let(:user) { build(:user, :readwrite) }

  before { Mobility.locale = nil }

  # -----------------------------------------------------------------
  # plants(anyName: "...") -- getPlantNameList
  # anyName matches scientific_name (iLIKE) OR common_names.name.
  # Using scientific_name as the search target -- it is a plain column,
  # no Mobility required.
  # -----------------------------------------------------------------
  describe 'anyName search (Plants/action.js getPlantNameList)' do
    let!(:plant) { create(:plant, :public, scientific_name: 'Solanum lycopersicum') }

    let(:query) do
      <<~GRAPHQL
        {
          plants(anyName: "Solanum lycopersicum") {
            nodes {
              id
              primaryCommonName
              scientificName
              varieties {
                nodes {
                  id
                  name
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns no GraphQL errors and the app-required shape' do
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'plants', 'nodes')
      expect(nodes).to be_an(Array)
      expect(nodes).not_to be_empty
      node = nodes.first
      expect(node).to have_key('id')
      expect(node).to have_key('primaryCommonName')
      expect(node).to have_key('scientificName')
      expect(node).to have_key('varieties')
      expect(node.dig('varieties', 'nodes')).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # plants(language: ...) full download -- getAllPlants
  # The app writes nodes to local SQLite and reads: id, primaryCommonName,
  # scientificName, description, createdBy, createdAt, updatedAt, ownedBy,
  # familyNames, varieties { nodes { id name description updatedAt ownedBy
  # createdBy createdAt } }
  # -----------------------------------------------------------------
  describe 'full plants download (Plants/action.js getAllPlants)' do
    let!(:plant) { create(:plant, :public, scientific_name: 'Manihot esculenta') }

    let(:query) do
      <<~GRAPHQL
        {
          plants(language: "en") {
            nodes {
              id
              primaryCommonName
              scientificName
              description
              createdBy
              createdAt
              updatedAt
              ownedBy
              familyNames
              varieties {
                nodes {
                  id
                  name
                  description
                  updatedAt
                  ownedBy
                  createdBy
                  createdAt
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns no errors and ownership fields as strings' do
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'plants', 'nodes')
      expect(nodes).to be_an(Array)
      node = nodes.find { |n| n['id'] }
      expect(node['createdBy']).to be_a(String)
      expect(node['ownedBy']).to be_a(String)
      expect(node.dig('varieties', 'nodes')).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # category(id: ...) { plants(first: 15) } -- getPlantList
  # Fields: totalCount, pageInfo, nodes with id/primaryCommonName/
  # familyNames/scientificName/images/description/translations
  # -----------------------------------------------------------------
  describe 'category plants paginated (Plants/action.js getPlantList)' do
    let(:category) { create(:category, :public) }
    let(:plant) { create(:plant, :public, scientific_name: 'Moringa oleifera') }

    before do
      plant.categories << category
    end

    let(:query) do
      cat_id = PlantApiSchema.id_from_object(category, Category, {})
      <<~GRAPHQL
        {
          category(id: "#{cat_id}", language: "en") {
            plants(first: 15, after: "") {
              totalCount
              pageInfo {
                endCursor
                startCursor
                hasNextPage
                hasPreviousPage
              }
              nodes {
                id
                primaryCommonName
                familyNames
                scientificName
                images(first: 1) {
                  nodes {
                    id
                    baseUrl
                  }
                }
                description
                translations {
                  locale
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns pagination shape with totalCount and pageInfo' do
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      conn = result.dig('data', 'category', 'plants')
      expect(conn).to have_key('totalCount')
      expect(conn.dig('pageInfo', 'hasNextPage')).not_to be_nil
      expect(conn.dig('pageInfo', 'endCursor')).not_to be_nil
      expect(conn.dig('pageInfo', 'startCursor')).not_to be_nil
      expect(conn.dig('pageInfo', 'hasPreviousPage')).not_to be_nil
      expect(conn['nodes']).to be_an(Array)
      node = conn['nodes'].first
      expect(node).to have_key('id')
      expect(node).to have_key('primaryCommonName')
      expect(node).to have_key('familyNames')
      expect(node).to have_key('scientificName')
      expect(node.dig('images', 'nodes')).to be_an(Array)
      expect(node).to have_key('translations')
    end
  end

  # -----------------------------------------------------------------
  # plants(visibility: PRIVATE) paginated -- getMyPlantList
  # -----------------------------------------------------------------
  describe 'my plants list (Plants/action.js getMyPlantList)' do
    let(:owner) { build(:user, :readwrite) }
    let(:other) { build(:user, :readwrite) }
    let!(:my_plant)    { create(:plant, :private, owned_by: owner.email, created_by: owner.email) }
    let!(:other_plant) { create(:plant, :private, owned_by: other.email, created_by: other.email) }

    let(:query) do
      <<~GRAPHQL
        {
          plants(visibility: PRIVATE, first: 15, after: "", language: "en") {
            totalCount
            pageInfo {
              endCursor
              startCursor
              hasNextPage
              hasPreviousPage
            }
            nodes {
              id
              primaryCommonName
              familyNames
              scientificName
              images(first: 1) {
                nodes {
                  id
                  baseUrl
                }
              }
              description
              translations {
                locale
              }
              varieties {
                nodes {
                  id
                  name
                  description
                  images(first: 1) {
                    nodes {
                      id
                      baseUrl
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns only the requesting user private plants, not other users private plants' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'plants', 'nodes')
      ids = nodes.map { |n| n['id'] }
      my_id = PlantApiSchema.id_from_object(my_plant, Plant, {})
      other_id = PlantApiSchema.id_from_object(other_plant, Plant, {})
      expect(ids).to include(my_id)
      expect(ids).not_to include(other_id)
    end

    it 'returns the full pagination and node shape' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      conn = result.dig('data', 'plants')
      expect(conn).to have_key('totalCount')
      expect(conn.dig('pageInfo', 'hasNextPage')).not_to be_nil
      node = conn['nodes'].first
      expect(node).to have_key('id')
      expect(node).to have_key('primaryCommonName')
      expect(node.dig('images', 'nodes')).to be_an(Array)
      expect(node.dig('varieties', 'nodes')).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # plant(id: ...) detail -- getPlantDetail
  # -----------------------------------------------------------------
  describe 'plant detail (Plants/action.js getPlantDetail)' do
    let(:plant) { create(:plant, :public, scientific_name: 'Ipomoea batatas') }

    let(:query) do
      pid = PlantApiSchema.id_from_object(plant, Plant, {})
      <<~GRAPHQL
        {
          plant(id: "#{pid}", language: "en") {
            id
            primaryCommonName
            description
            scientificName
            familyNames
            images(first: 1) {
              nodes {
                baseUrl
              }
            }
            cookingAndNutrition
            cultivation
            harvestingAndSeedProduction
            origin
            uses
            pestsAndDiseases
            attribution
          }
        }
      GRAPHQL
    end

    it 'returns no errors and every field the app accesses' do
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      node = result.dig('data', 'plant')
      %w[id primaryCommonName description scientificName familyNames
         cookingAndNutrition cultivation harvestingAndSeedProduction
         origin uses pestsAndDiseases attribution].each do |field|
        expect(node).to have_key(field), "expected field '#{field}' to be present"
      end
      expect(node.dig('images', 'nodes')).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # categories(first: 15) -- getPlantCategoryList
  # -----------------------------------------------------------------
  describe 'categories list (Plants/action.js getPlantCategoryList)' do
    let!(:category) { create(:category, :public) }

    let(:query) do
      <<~GRAPHQL
        {
          categories(first: 15, language: "en", after: "") {
            totalCount
            pageInfo {
              endCursor
              startCursor
              hasNextPage
              hasPreviousPage
            }
            nodes {
              id
              name
              description
              images(first: 1) {
                nodes {
                  id
                  baseUrl
                }
              }
              translations {
                locale
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns pagination and node shape the app depends on' do
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      conn = result.dig('data', 'categories')
      expect(conn).to have_key('totalCount')
      expect(conn.dig('pageInfo', 'hasNextPage')).not_to be_nil
      expect(conn['nodes']).to be_an(Array)
      node = conn['nodes'].first
      expect(node).to have_key('id')
      expect(node).to have_key('name')
      expect(node.dig('images', 'nodes')).to be_an(Array)
      expect(node).to have_key('translations')
    end
  end

  # -----------------------------------------------------------------
  # specimens(first: 3) home list -- getSeedTrialReportsListHome
  # The app uses visibility: PUBLIC (specimens list)
  # -----------------------------------------------------------------
  describe 'specimens home list (SeedTrialReports/action.js getSeedTrialReportsListHome)' do
    let!(:specimen) { create(:specimen, :public, owned_by: user.email, created_by: user.email) }

    let(:query) do
      <<~GRAPHQL
        {
          specimens(first: 3, language: "en", after: "") {
            pageInfo {
              endCursor
              startCursor
              hasNextPage
              hasPreviousPage
            }
            nodes {
              createdBy
              id
              lifeCycleEvents {
                nodes {
                  datetime
                  id
                }
              }
              name
              notes
              ownedBy
              recommended
              savedSeed
              successful
              terminated
              visibility
            }
          }
        }
      GRAPHQL
    end

    it 'returns no errors and app-required specimen fields' do
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'specimens', 'nodes')
      expect(nodes).to be_an(Array)
      expect(nodes).not_to be_empty
      node = nodes.first
      %w[createdBy id name notes ownedBy recommended savedSeed successful terminated visibility].each do |f|
        expect(node).to have_key(f), "expected field '#{f}'"
      end
      expect(node.dig('lifeCycleEvents', 'nodes')).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # specimens(first: 15) full list -- getSeedTrialReportsList
  # -----------------------------------------------------------------
  describe 'specimens full list with __typename (SeedTrialReports/action.js getSeedTrialReportsList)' do
    let!(:specimen) { create(:specimen, :public, owned_by: user.email, created_by: user.email) }

    let(:query) do
      <<~GRAPHQL
        {
          specimens(first: 15, language: "en", after: "") {
            pageInfo {
              hasNextPage
              hasPreviousPage
              endCursor
              startCursor
            }
            nodes {
              id
              images {
                nodes {
                  id
                  baseUrl
                }
              }
              name
              notes
              ownedBy
              plant {
                id
                primaryCommonName
                varieties {
                  nodes {
                    id
                    name
                  }
                }
              }
              lifeCycleEvents {
                nodes {
                  id
                  __typename
                  datetime
                  notes
                  images {
                    nodes {
                      id
                      baseUrl
                    }
                  }
                }
              }
              visibility
              willShareSeed
              willPlantAgain
              successful
              recommended
              savedSeed
            }
          }
        }
      GRAPHQL
    end

    it 'returns __typename on each life cycle event node' do
      create(:harvest_event, specimen: specimen, quantity: 3.0, unit: 'weight', quality: 7)
      result = PlantApiSchema.execute(query, context: { current_user: user })
      expect(result['errors']).to be_nil
      # Find the specimen that owns the event
      s_node = result.dig('data', 'specimens', 'nodes').find { |n| n['id'] }
      expect(s_node).to have_key('visibility')
      lce_nodes = s_node.dig('lifeCycleEvents', 'nodes')
      expect(lce_nodes).to be_an(Array)
      lce_node = lce_nodes.find { |n| n['__typename'] }
      expect(lce_node['__typename']).to eq('HarvestEvent') if lce_node
    end
  end

  # -----------------------------------------------------------------
  # specimens(visibility: PRIVATE) sync-down with inline fragments
  # Ref: SeedTrialReports/action.js getSeedTrialReportsFromServer
  # Asserts: the aliased HarvestEvent fields (quantityHE, unitHE,
  # qualityHE), MovementEvent (quantityME, unitME, location),
  # GerminationEvent (qualityGE, percentGE), FloweringEvent (percentFE),
  # and ownership isolation.
  # -----------------------------------------------------------------
  describe 'specimens sync-down PRIVATE with aliased event fragments' do
    let(:owner) { build(:user, :readwrite) }
    let(:other) { build(:user, :readwrite) }
    let!(:my_spec)    { create(:specimen, :private, owned_by: owner.email, created_by: owner.email) }
    let!(:other_spec) { create(:specimen, :private, owned_by: other.email, created_by: other.email) }
    let!(:loc) { create(:location, owned_by: owner.email, created_by: owner.email) }

    before do
      create(:harvest_event, specimen: my_spec, quantity: 5.0, unit: 'weight', quality: 8)
      create(:movement_event, specimen: my_spec, location: loc, quantity: 10.0, unit: 'count',
                              between_row_spacing: 30, in_row_spacing: 15)
    end

    let(:query) do
      <<~GRAPHQL
        {
          specimens(language: "en", visibility: PRIVATE) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              endCursor
              startCursor
            }
            nodes {
              id
              images {
                nodes {
                  id
                  baseUrl
                }
              }
              name
              notes
              ownedBy
              updatedAt
              createdAt
              plant {
                id
                primaryCommonName
              }
              variety {
                name
                id
              }
              lifeCycleEvents {
                nodes {
                  id
                  __typename
                  datetime
                  updatedAt
                  notes
                  deleted
                  ... on AcquireEvent {
                    accession
                    source
                    condition
                  }
                  ... on PlantingEvent {
                    location {
                      id
                      name
                    }
                  }
                  ... on SoilPreparationEvent {
                    soilPreparation
                  }
                  ... on MovementEvent {
                    quantityME: quantity
                    unitME: unit
                    location {
                      id
                      name
                    }
                    betweenRowSpacing
                    inRowSpacing
                  }
                  ... on HarvestEvent {
                    quantityHE: quantity
                    unitHE: unit
                    qualityHE: quality
                  }
                  ... on GerminationEvent {
                    qualityGE: quality
                    percentGE: percent
                  }
                  ... on FloweringEvent {
                    percentFE: percent
                  }
                  images {
                    nodes {
                      id
                      baseUrl
                    }
                  }
                }
              }
              visibility
              willShareSeed
              willPlantAgain
              successful
              recommended
              savedSeed
              evaluatedAt
            }
          }
        }
      GRAPHQL
    end

    it 'returns only the requesting users private specimens, not other users' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'specimens', 'nodes')
      ids = nodes.map { |n| n['id'] }
      my_id    = PlantApiSchema.id_from_object(my_spec, Specimen, {})
      other_id = PlantApiSchema.id_from_object(other_spec, Specimen, {})
      expect(ids).to include(my_id)
      expect(ids).not_to include(other_id)
    end

    it 'resolves aliased HarvestEvent fields (quantityHE, unitHE, qualityHE)' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      nodes = result.dig('data', 'specimens', 'nodes')
      my_s = nodes.find { |n| n['id'] == PlantApiSchema.id_from_object(my_spec, Specimen, {}) }
      he = my_s.dig('lifeCycleEvents', 'nodes').find { |e| e['__typename'] == 'HarvestEvent' }
      expect(he).not_to be_nil
      expect(he).to have_key('quantityHE')
      expect(he).to have_key('unitHE')
      expect(he).to have_key('qualityHE')
      expect(he['quantityHE']).to eq(5.0)
    end

    it 'resolves aliased MovementEvent fields (quantityME, unitME, location, spacing)' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      nodes = result.dig('data', 'specimens', 'nodes')
      my_s = nodes.find { |n| n['id'] == PlantApiSchema.id_from_object(my_spec, Specimen, {}) }
      me = my_s.dig('lifeCycleEvents', 'nodes').find { |e| e['__typename'] == 'MovementEvent' }
      expect(me).not_to be_nil
      expect(me).to have_key('quantityME')
      expect(me).to have_key('unitME')
      expect(me).to have_key('betweenRowSpacing')
      expect(me).to have_key('inRowSpacing')
      expect(me.dig('location', 'id')).to be_present
      expect(me.dig('location', 'name')).to be_present
    end

    it 'exposes ownedBy as a string on the specimen node' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      node = result.dig('data', 'specimens', 'nodes').first
      expect(node['ownedBy']).to be_a(String)
    end

    it 'exposes evaluatedAt on the specimen node' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      node = result.dig('data', 'specimens', 'nodes').first
      expect(node).to have_key('evaluatedAt')
    end
  end

  # -----------------------------------------------------------------
  # varieties(visibility: PRIVATE) sync-down -- fetchCustomVarietyFromServer
  # -----------------------------------------------------------------
  describe 'varieties sync-down PRIVATE (SeedTrialReports/action.js fetchCustomVarietyFromServer)' do
    let(:owner) { build(:user, :readwrite) }
    let(:other) { build(:user, :readwrite) }
    let!(:my_variety)    { create(:variety, :private, owned_by: owner.email, created_by: owner.email) }
    let!(:other_variety) { create(:variety, :private, owned_by: other.email, created_by: other.email) }

    let(:query) do
      <<~GRAPHQL
        {
          varieties(language: "en", visibility: PRIVATE) {
            nodes {
              id
              name
              description
              updatedAt
              ownedBy
              createdBy
              createdAt
              plant {
                id
                primaryCommonName
                scientificName
                description
                createdBy
                createdAt
                updatedAt
                ownedBy
                familyNames
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns only the requesting users private varieties' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'varieties', 'nodes')
      ids = nodes.map { |n| n['id'] }
      my_id    = PlantApiSchema.id_from_object(my_variety, Variety, {})
      other_id = PlantApiSchema.id_from_object(other_variety, Variety, {})
      expect(ids).to include(my_id)
      expect(ids).not_to include(other_id)
    end

    it 'includes nested plant ownership fields' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      node = result.dig('data', 'varieties', 'nodes').first
      plant_node = node['plant']
      expect(plant_node).to have_key('ownedBy')
      expect(plant_node).to have_key('createdBy')
      expect(plant_node).to have_key('familyNames')
    end
  end

  # -----------------------------------------------------------------
  # locations(visibility: PRIVATE) sync-down -- fetchLocationsFromServer
  # -----------------------------------------------------------------
  describe 'locations sync-down PRIVATE (SeedTrialReports/action.js fetchLocationsFromServer)' do
    let(:owner) { build(:user, :readwrite) }
    let(:other) { build(:user, :readwrite) }
    let!(:my_loc)    { create(:location, :private, owned_by: owner.email, created_by: owner.email) }
    let!(:other_loc) { create(:location, :private, owned_by: other.email, created_by: other.email) }

    let(:query) do
      <<~GRAPHQL
        {
          locations(language: "en", visibility: PRIVATE) {
            nodes {
              id
              name
              soilQuality
              slope
              altitude
              irrigated
              latitude
              longitude
              visibility
              ownedBy
              updatedAt
            }
          }
        }
      GRAPHQL
    end

    it 'returns only the requesting users private locations' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      expect(result['errors']).to be_nil
      nodes = result.dig('data', 'locations', 'nodes')
      ids = nodes.map { |n| n['id'] }
      my_id    = PlantApiSchema.id_from_object(my_loc, Location, {})
      other_id = PlantApiSchema.id_from_object(other_loc, Location, {})
      expect(ids).to include(my_id)
      expect(ids).not_to include(other_id)
    end

    it 'includes all location fields the app syncs to local DB' do
      result = PlantApiSchema.execute(query, context: { current_user: owner })
      node = result.dig('data', 'locations', 'nodes').first
      %w[id name soilQuality slope altitude irrigated latitude longitude visibility ownedBy updatedAt].each do |f|
        expect(node).to have_key(f), "expected field '#{f}'"
      end
    end
  end
end
