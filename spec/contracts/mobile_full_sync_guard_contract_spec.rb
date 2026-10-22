# frozen_string_literal: true

require 'rails_helper'

# Contract: the mobile full-sync guard (API-3) and the mobile category-browse
# safety filter (API-4).
#
# The frozen mobile app is the only client that calls plants() with neither
# first: nor last:. It writes every returned node into its local plant table
# and shows those plants without any safety information. Once other
# organizations' plants become public, that call would pull tens of thousands
# of them onto every device. The guard therefore restricts an UNPAGINATED
# plants() call to plants owned by an allow-listed organization
# (MOBILE_FULL_SYNC_OWNER_ORG_IDS, default the production ECHO organization),
# public or private, for every caller -- anonymous, member, super-admin.
#
# One exception, kept on purpose: the caller's OWN personal organization.
# The app's custom-plant sync (SeedTrialReports/action.js
# fetchCustomPlantsFromServer) is the unpaginated plants(visibility: PRIVATE)
# call, and syncDownCustomPlantData DELETES from the device every custom
# plant the server no longer returns. Without the exception, deploying the
# guard would wipe every mobile user's custom plants from their phone.
#
# Paginated calls (first: or last: given) are untouched, and so are the
# admin SPA and ECHOcommunity, which always paginate.
#
# The category browse (Plants/action.js getPlantList) is paginated, so the
# guard above does not cover it. Instead, for anonymous callers, plants of
# organizations NOT on the allow-list are hidden when they carry a safety flag
# (safety level poisonous or caution, or edibility uncertain). The app sends
# its browse token in a nonstandard "Authentication:" header that the API
# never reads (docs/ownership-redesign/discovery.md), so that browse is
# always anonymous; authenticated callers (the admin SPA) see the full set.
RSpec.describe 'Mobile full-sync guard contract', type: :graphql_query do
  # The production ECHO organization id: the code default for the allow-list,
  # so these examples exercise the default rather than a stubbed value.
  let(:echo_org_id) { MobileFullSyncConfig::DEFAULT_OWNER_ORG_IDS.first }
  let!(:echo_org) do
    Organization.find_by(id: echo_org_id) ||
      create(:organization, :real, external_idp_id: echo_org_id, name: 'ECHO')
  end
  let!(:other_org) { create(:organization, :real, name: 'Other Source') }

  let(:author) { 'author@example.org' }

  let!(:echo_public) do
    create(:plant, :public, scientific_name: 'Moringa oleifera',
                            owner_organization_id: echo_org.id, owned_by: author)
  end
  let!(:echo_private) do
    create(:plant, :private, scientific_name: 'Moringa stenopetala',
                             owner_organization_id: echo_org.id, owned_by: author)
  end
  let!(:other_public) do
    create(:plant, :public, scientific_name: 'Moringa peregrina',
                            owner_organization_id: other_org.id, owned_by: author)
  end
  let!(:other_private) do
    create(:plant, :private, scientific_name: 'Moringa concanensis',
                             owner_organization_id: other_org.id, owned_by: author)
  end

  let(:other_ids) { [other_public, other_private].map { |p| gid(p) } }
  let(:echo_ids) { [echo_public, echo_private].map { |p| gid(p) } }

  def gid(record)
    PlantApiSchema.id_from_object(record, record.class, {})
  end

  def run(query, user, variables: {})
    PlantApiSchema.execute(query, context: { current_user: user }, variables: variables)
  end

  def node_ids(result, *path)
    nodes = result.dig('data', *path, 'nodes') ||
            result.dig('data', *path, 'edges')&.map { |e| e['node'] }
    Array(nodes).map { |n| n['id'] }
  end

  def org_member(org, role: 'org_admin', trust: 2)
    principal = create(:principal)
    User.new(
      'uid' => principal.external_uid,
      'email' => principal.email,
      'trust_levels' => { 'plant' => trust },
      'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }]
    ).tap do |u|
      u.principal = principal
      u.personal_organization = Organization.personal_for!(principal)
    end
  end

  let(:super_admin) { build(:user, :superadmin) }
  let(:other_member) { org_member(other_org) }

  # Verbatim from Plants/action.js getAllPlants (language substituted).
  let(:get_all_plants) do
    <<~GRAPHQL
      {
          plants(language: "en")#{' '}
          {
              nodes#{' '}
              {
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

  # Verbatim from SeedTrialReports/action.js fetchCustomPlantsFromServer.
  let(:fetch_custom_plants) do
    <<~GRAPHQL
      {
        plants(language: "en", visibility: PRIVATE)#{' '}
        {
            nodes#{' '}
            {
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

  # Verbatim from Plants/action.js getPlantNameList (name substituted).
  let(:get_plant_name_list) do
    <<~GRAPHQL
      {
          plants(anyName: "Moringa") {
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

  describe 'unpaginated plants() (getAllPlants)' do
    it 'returns only the allow-listed organization to an anonymous caller' do
      result = run(get_all_plants, nil)
      expect(result['errors']).to be_nil
      expect(node_ids(result, 'plants')).to contain_exactly(gid(echo_public))
    end

    it 'returns 0 rows of other organizations to a super-admin, public or private' do
      result = run(get_all_plants, super_admin)
      expect(result['errors']).to be_nil
      ids = node_ids(result, 'plants')
      expect(ids).to match_array(echo_ids)
      expect(ids & other_ids).to be_empty
    end

    it 'returns 0 rows of their own organization to a member of a non-allow-listed organization' do
      result = run(get_all_plants, other_member)
      expect(result['errors']).to be_nil
      ids = node_ids(result, 'plants')
      expect(ids).to contain_exactly(gid(echo_public))
      expect(ids & other_ids).to be_empty
    end

    it 'keeps private plants of the allow-listed organization for its members' do
      result = run(get_all_plants, org_member(echo_org))
      expect(node_ids(result, 'plants')).to match_array(echo_ids)
    end

    it 'keeps the caller own personal-organization plants' do
      user = build(:user, :readwrite)
      own = create(:plant, :private, scientific_name: 'Moringa drouhardii', owned_by: user.email)
      expect(own.owner_organization_id).to eq(user.personal_organization.id)

      ids = node_ids(run(get_all_plants, user), 'plants')
      expect(ids).to contain_exactly(gid(echo_public), gid(own))
    end

    it 'treats an explicit null first: variable as unpaginated' do
      query = <<~GRAPHQL
        query($f: Int) { plants(first: $f) { totalCount nodes { id } } }
      GRAPHQL
      result = run(query, super_admin, variables: { 'f' => nil })
      expect(result['errors']).to be_nil
      expect(node_ids(result, 'plants')).to match_array(echo_ids)
      expect(result.dig('data', 'plants', 'totalCount')).to eq(2)
    end

    it 'guards every unpaginated variant, including anyName (getPlantNameList)' do
      result = run(get_plant_name_list, super_admin)
      expect(result['errors']).to be_nil
      expect(node_ids(result, 'plants')).to match_array(echo_ids)
    end
  end

  describe 'unpaginated plants(visibility: PRIVATE) (fetchCustomPlantsFromServer)' do
    it 'returns 0 rows of other organizations to a super-admin' do
      ids = node_ids(run(fetch_custom_plants, super_admin), 'plants')
      expect(ids).to contain_exactly(gid(echo_private))
    end

    it 'returns 0 rows of their own organization to a member of a non-allow-listed organization' do
      ids = node_ids(run(fetch_custom_plants, other_member), 'plants')
      expect(ids & other_ids).to be_empty
    end

    it 'still returns the caller own custom plants, so the device keeps them' do
      user = build(:user, :readwrite)
      own = create(:plant, :private, scientific_name: 'Moringa arborea', owned_by: user.email)

      result = run(fetch_custom_plants, user)
      expect(result['errors']).to be_nil
      expect(node_ids(result, 'plants')).to contain_exactly(gid(own))
    end
  end

  describe 'paginated plants() is unaffected' do
    let(:paginated) do
      <<~GRAPHQL
        query($first: Int, $last: Int) {
          plants(first: $first, last: $last) { totalCount nodes { id } }
        }
      GRAPHQL
    end

    it 'returns every organization to a super-admin with first:' do
      result = run(paginated, super_admin, variables: { 'first' => 15 })
      expect(node_ids(result, 'plants')).to match_array(echo_ids + other_ids)
      expect(result.dig('data', 'plants', 'totalCount')).to eq(4)
    end

    it 'returns every organization to a super-admin with only last:' do
      result = run(paginated, super_admin, variables: { 'last' => 2 })
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'plants', 'totalCount')).to eq(4)
      expect(node_ids(result, 'plants').size).to eq(2)
    end

    it 'returns their own organization to a member of a non-allow-listed organization' do
      result = run(paginated, other_member, variables: { 'first' => 15 })
      expect(node_ids(result, 'plants')).to include(*other_ids)
    end

    it 'returns both organizations to an anonymous caller with first: 15' do
      result = run(paginated, nil, variables: { 'first' => 15 })
      expect(node_ids(result, 'plants')).to contain_exactly(gid(echo_public), gid(other_public))
    end
  end

  describe 'allow-list configuration' do
    it 'follows the configured organizations instead of the default' do
      allow(MobileFullSyncGuard).to receive(:owner_organization_ids).and_return([other_org.id])
      ids = node_ids(run(get_all_plants, super_admin), 'plants')
      expect(ids).to match_array(other_ids)
    end
  end

  # -----------------------------------------------------------------
  # category(id) { plants(first: 15) } -- getPlantList, always anonymous
  # -----------------------------------------------------------------
  describe 'category browse safety filter (getPlantList)' do
    let(:category) { create(:category, :public) }

    let!(:other_poisonous) do
      create(:plant, :public, scientific_name: 'Abrus precatorius', safety_level: 'poisonous',
                              owner_organization_id: other_org.id, owned_by: author)
    end
    let!(:other_caution) do
      create(:plant, :public, scientific_name: 'Jatropha curcas', safety_level: 'caution',
                              owner_organization_id: other_org.id, owned_by: author)
    end
    let!(:other_uncertain) do
      create(:plant, :public, scientific_name: 'Cycas revoluta', edibility_uncertain: true,
                              owner_organization_id: other_org.id, owned_by: author)
    end
    let!(:echo_poisonous) do
      create(:plant, :public, scientific_name: 'Manihot esculenta', safety_level: 'poisonous',
                              owner_organization_id: echo_org.id, owned_by: author)
    end

    before do
      category.plants << [echo_public, other_public, other_poisonous, other_caution,
                          other_uncertain, echo_poisonous]
    end

    # Verbatim from Plants/action.js getPlantList (id/lang/cursor substituted).
    let(:get_plant_list) do
      <<~GRAPHQL
        {
            category(id: "#{gid(category)}",language: "en") {
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

    it 'hides safety-flagged plants of non-allow-listed organizations from anonymous callers' do
      result = run(get_plant_list, nil)
      expect(result['errors']).to be_nil
      expect(node_ids(result, 'category', 'plants'))
        .to contain_exactly(gid(echo_public), gid(other_public), gid(echo_poisonous))
      expect(result.dig('data', 'category', 'plants', 'totalCount')).to eq(3)
    end

    it 'never filters the allow-listed organization, even when flagged' do
      ids = node_ids(run(get_plant_list, nil), 'category', 'plants')
      expect(ids).to include(gid(echo_poisonous))
    end

    it 'shows the full set to authenticated callers (admin SPA CategoryDetail)' do
      query = <<~GRAPHQL
        query($id: ID!) {
          category(id: $id) { plants(first: 20) { totalCount edges { node { id } } } }
        }
      GRAPHQL
      [build(:user, :readwrite), super_admin].each do |user|
        result = run(query, user, variables: { 'id' => gid(category) })
        expect(result.dig('data', 'category', 'plants', 'totalCount')).to eq(6)
      end
    end
  end
end
