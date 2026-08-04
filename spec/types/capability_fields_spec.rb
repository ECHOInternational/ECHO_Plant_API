# frozen_string_literal: true

require 'rails_helper'

# Parameterized capability matrix for Types::Concerns::CapabilityFields on Plant.
# Verifies that canEdit, canDelete, canRestore in GraphQL agree with the Pundit
# policy methods update?, soft_delete?, restore? for every relevant actor.
#
# Actor definitions:
#   :anonymous       - no user (nil)
#   :member          - org member role (read only)
#   :contributor     - created the record (update_own)
#   :non_creator_contrib - contributor but did NOT create the record
#   :editor          - org editor (update_any, no soft_delete)
#   :steward         - org steward (soft_delete + restore)
#   :owner           - the record's own owner (trust 2, org_admin of their
#                      personal organization, which is where the backfill put
#                      the records they owned by email)
#   :admin           - trust 9, which S7 demoted to an ordinary writer
RSpec.describe 'CapabilityFields on PlantType', type: :graphql_query do
  let(:org) { create(:organization, :real) }

  def gql_query
    <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          canEdit
          canDelete
          canRestore
        }
      }
    GRAPHQL
  end

  def execute(plant, user)
    plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
    PlantApiSchema.execute(
      gql_query,
      context: { current_user: user },
      variables: { id: plant_id }
    )
  end

  def build_org_user(org, role:, trust: 2)
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

  # A plant whose owner_organization is the shared org
  let(:plant) { create(:plant, :public, owner_organization_id: org.id, owned_by: 'other@example.com') }

  describe ':anonymous user' do
    it 'returns false for all capability fields (anonymous sees public plants)' do
      result = execute(plant, nil)
      data = result.dig('data', 'plant')
      expect(result['errors']).to be_nil
      expect(data['canEdit']).to be false
      expect(data['canDelete']).to be false
      expect(data['canRestore']).to be false
    end
  end

  describe ':member role' do
    let(:user) { build_org_user(org, role: 'member') }

    it 'cannot edit, delete, or restore' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be false
      expect(data['canDelete']).to be false
      expect(data['canRestore']).to be false
    end
  end

  describe ':contributor (non-creator)' do
    let(:user) { build_org_user(org, role: 'contributor') }

    it 'cannot edit (no update_own without creation), cannot delete, cannot restore' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be false
      expect(data['canDelete']).to be false
      expect(data['canRestore']).to be false
    end
  end

  describe ':contributor who created the record' do
    let(:principal) { create(:principal) }
    let(:user) do
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'contributor' } }]
      ).tap do |u|
        u.principal = principal
        u.personal_organization = Organization.personal_for!(principal)
      end
    end
    let(:plant) do
      create(:plant, :public,
             owner_organization_id: org.id,
             owned_by: 'other@example.com',
             created_by_principal_id: principal.id)
    end

    it 'can edit (update_own), cannot delete, cannot restore' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be true
      expect(data['canDelete']).to be false
      expect(data['canRestore']).to be false
    end
  end

  describe ':editor role' do
    let(:user) { build_org_user(org, role: 'editor') }

    it 'can edit (update_any), cannot delete (no soft_delete), cannot restore' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be true
      expect(data['canDelete']).to be false
      expect(data['canRestore']).to be false
    end
  end

  describe ':steward role' do
    let(:user) { build_org_user(org, role: 'steward') }

    it 'can edit, can delete (soft_delete), can restore' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be true
      expect(data['canDelete']).to be true
      expect(data['canRestore']).to be true
    end
  end

  describe ':owner (trust 2, org_admin of their own personal organization)' do
    let(:owner_email) { 'plant-owner@example.com' }
    let(:user) { build(:user, :readwrite, email: owner_email) }
    # Deliberately not pinned to the unrelated real org this file uses
    # elsewhere: a record owned by this email lives in this person's personal
    # organization. Pinning it elsewhere modelled a row the backfill could not
    # produce and only passed through the removed email rule.
    let(:plant) do
      create(:plant, :private, owned_by: owner_email)
    end

    it 'can edit, delete and restore its own record' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be true
      expect(data['canDelete']).to be true
      expect(data['canRestore']).to be true
    end
  end

  # S7 (design.md D3): trust 9 stopped being a global admin once ECHO-org
  # memberships covered staff. With no membership in the owning organization it
  # is an ordinary writer, and the capability fields the SPA renders its buttons
  # from have to say so -- otherwise the UI offers actions the API will refuse.
  describe ':admin (trust 9, no membership in the owning organization)' do
    let(:user) { build(:user, :admin) }
    let(:plant) { create(:plant, :public, owned_by: 'someone@example.com') }

    it 'cannot edit, delete or restore another organization\'s record' do
      data = execute(plant, user).dig('data', 'plant')
      expect(data['canEdit']).to be false
      expect(data['canDelete']).to be false
      expect(data['canRestore']).to be false
    end
  end

  # Verify the new ownership/provenance fields resolve correctly
  describe 'new ownership/provenance fields' do
    let(:source_org) { create(:organization, :real) }
    let(:principal_record) { create(:principal) }
    let(:plant) do
      create(:plant, :public,
             owner_organization_id: org.id,
             source_organization_id: source_org.id,
             created_by_principal_id: principal_record.id,
             owned_by: 'old@example.com')
    end
    let(:user) { build(:user, :readwrite) }

    let(:fields_query) do
      <<~GRAPHQL
        query($id: ID!) {
          plant(id: $id) {
            ownerOrganization { id kind name }
            sourceOrganization { id kind name }
            createdByPrincipal { id email }
            publicationState
            accessLevel
            deletedAt
          }
        }
      GRAPHQL
    end

    it 'resolves ownerOrganization from owner_organization_id' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        fields_query,
        context: { current_user: user },
        variables: { id: plant_id }
      )
      expect(result['errors']).to be_nil
      owner = result.dig('data', 'plant', 'ownerOrganization')
      expect(owner).not_to be_nil
      expect(owner['kind']).to eq 'real'
    end

    it 'resolves sourceOrganization from source_organization_id' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        fields_query,
        context: { current_user: user },
        variables: { id: plant_id }
      )
      source = result.dig('data', 'plant', 'sourceOrganization')
      expect(source).not_to be_nil
      expect(source['kind']).to eq 'real'
    end

    it 'resolves createdByPrincipal from created_by_principal_id' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        fields_query,
        context: { current_user: user },
        variables: { id: plant_id }
      )
      principal_node = result.dig('data', 'plant', 'createdByPrincipal')
      expect(principal_node).not_to be_nil
      expect(principal_node['email']).to eq principal_record.email
    end

    it 'returns null ownerOrganization when not set', :pre_backfill do
      # Needs the pre-backfill shape explicitly now that factories stamp
      # ownership. Production has no such rows -- S7 puts NOT NULL on the
      # column -- but the resolver's nil branch is still worth pinning.
      bare_plant = create(:plant, :public, :unowned, owned_by: user.email)
      plant_id = PlantApiSchema.id_from_object(bare_plant, Plant, {})
      result = PlantApiSchema.execute(
        fields_query,
        context: { current_user: user },
        variables: { id: plant_id }
      )
      expect(result.dig('data', 'plant', 'ownerOrganization')).to be_nil
    end
  end

  # Verify deprecation annotations are present in introspection
  describe 'deprecation annotations (introspection)' do
    let(:introspection_query) do
      <<~GRAPHQL
        query {
          __type(name: "Plant") {
            fields(includeDeprecated: true) {
              name
              isDeprecated
              deprecationReason
            }
          }
        }
      GRAPHQL
    end

    it 'marks ownedBy as deprecated' do
      result = PlantApiSchema.execute(introspection_query, context: { current_user: nil })
      fields = result.dig('data', '__type', 'fields')
      owned_by_field = fields.find { |f| f['name'] == 'ownedBy' }
      expect(owned_by_field).not_to be_nil
      expect(owned_by_field['isDeprecated']).to be true
      expect(owned_by_field['deprecationReason']).to be_present
    end

    it 'marks createdBy as deprecated' do
      result = PlantApiSchema.execute(introspection_query, context: { current_user: nil })
      fields = result.dig('data', '__type', 'fields')
      created_by_field = fields.find { |f| f['name'] == 'createdBy' }
      expect(created_by_field).not_to be_nil
      expect(created_by_field['isDeprecated']).to be true
    end

    it 'marks visibility as deprecated' do
      result = PlantApiSchema.execute(introspection_query, context: { current_user: nil })
      fields = result.dig('data', '__type', 'fields')
      visibility_field = fields.find { |f| f['name'] == 'visibility' }
      expect(visibility_field).not_to be_nil
      expect(visibility_field['isDeprecated']).to be true
    end
  end
end
