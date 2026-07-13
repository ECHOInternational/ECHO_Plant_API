# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'syncConflicts query', type: :graphql_query do
  let(:query_string) do
    <<~GRAPHQL
      query($status: SyncConflictStatusEnum) {
        syncConflicts(status: $status) {
          id
          conflictType
          status
        }
      }
    GRAPHQL
  end

  def execute(user, status: nil)
    vars = {}
    vars[:status] = status if status
    PlantApiSchema.execute(
      query_string,
      context: { current_user: user },
      variables: vars
    )
  end

  # Builds a User with an org claim for the given role.
  def build_org_user(org, role:, trust: 4)
    principal = create(:principal)
    User.new(
      'uid' => principal.external_uid,
      'email' => principal.email,
      'trust_levels' => { 'plant' => trust },
      'organizations' => [{
        'id' => org.id,
        'name' => org.name,
        'roles' => { 'plant' => role }
      }]
    ).tap do |u|
      u.principal = principal
      u.personal_organization = Organization.personal_for!(principal)
    end
  end

  let(:org)          { create(:organization, :real) }
  let(:other_org)    { create(:organization, :real) }
  let(:data_source)  { create(:data_source, organization: org) }

  let(:plant_in_org) do
    create(:plant, owner_organization_id: org.id, owned_by: 'owner@example.com')
  end
  let(:plant_in_other_org) do
    create(:plant, owner_organization_id: other_org.id, owned_by: 'other@example.com')
  end

  let!(:conflict_in_org) do
    create(
      :sync_conflict,
      syncable: plant_in_org,
      data_source: data_source,
      conflict_type: 'content',
      status: 'open'
    )
  end
  let!(:conflict_in_other_org) do
    create(
      :sync_conflict,
      syncable: plant_in_other_org,
      data_source: data_source,
      conflict_type: 'content',
      status: 'open'
    )
  end
  let!(:resolved_conflict_in_org) do
    create(
      :sync_conflict,
      :resolved,
      syncable: plant_in_org,
      data_source: data_source
    )
  end

  # ---------------------------------------------------------------------------
  # Anonymous: empty
  # ---------------------------------------------------------------------------
  context 'when anonymous' do
    it 'returns an empty list' do
      result = execute(nil)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'syncConflicts')).to eq []
    end
  end

  # ---------------------------------------------------------------------------
  # User with resolve_conflicts in org: sees conflicts for their org
  # ---------------------------------------------------------------------------
  context 'when user has resolve_conflicts in org' do
    let(:user) { build_org_user(org, role: 'editor') }

    it 'returns conflicts belonging to their org' do
      result = execute(user)
      ids = result.dig('data', 'syncConflicts').map { |c| c['id'] }
      conflict_in_org_gid  = PlantApiSchema.id_from_object(conflict_in_org, SyncConflict, {})
      conflict_other_gid   = PlantApiSchema.id_from_object(conflict_in_other_org, SyncConflict, {})
      resolved_gid         = PlantApiSchema.id_from_object(resolved_conflict_in_org, SyncConflict, {})

      expect(ids).to include(conflict_in_org_gid)
      expect(ids).to include(resolved_gid)
      expect(ids).not_to include(conflict_other_gid)
    end
  end

  # ---------------------------------------------------------------------------
  # User without resolve_conflicts: sees nothing
  # ---------------------------------------------------------------------------
  context 'when user has no resolve_conflicts capability (member role)' do
    let(:user) { build_org_user(org, role: 'member') }

    it 'returns empty list' do
      result = execute(user)
      expect(result.dig('data', 'syncConflicts')).to eq []
    end
  end

  # ---------------------------------------------------------------------------
  # Admin: sees all conflicts
  # ---------------------------------------------------------------------------
  context 'when user is admin (trust 9)' do
    let(:user) { build(:user, :admin) }

    it 'returns all conflicts across orgs' do
      result = execute(user)
      ids = result.dig('data', 'syncConflicts').map { |c| c['id'] }
      all_conflict_gids = [conflict_in_org, conflict_in_other_org, resolved_conflict_in_org].map do |c|
        PlantApiSchema.id_from_object(c, SyncConflict, {})
      end

      all_conflict_gids.each do |gid|
        expect(ids).to include(gid)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Status filter
  # ---------------------------------------------------------------------------
  context 'status filter' do
    let(:user) { build(:user, :admin) }

    it 'filters to open conflicts only' do
      result = execute(user, status: 'open')
      statuses = result.dig('data', 'syncConflicts').map { |c| c['status'] }
      expect(statuses).to all(eq('open'))
    end

    it 'filters to resolved conflicts only' do
      result = execute(user, status: 'resolved')
      statuses = result.dig('data', 'syncConflicts').map { |c| c['status'] }
      expect(statuses).to all(eq('resolved'))
    end
  end
end
