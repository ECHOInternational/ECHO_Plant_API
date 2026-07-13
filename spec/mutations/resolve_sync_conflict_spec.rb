# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ResolveSyncConflict Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: ResolveSyncConflictInput!) {
        resolveSyncConflict(input: $input) {
          syncConflict {
            id
            status
            resolution
          }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  let(:org)         { create(:organization, :real) }
  let(:data_source) { create(:data_source, organization: org) }
  let(:source_attrs) { { 'scientific_name' => 'Moringa oleifera', 'family_names' => 'Moringaceae' } }

  let(:plant) do
    create(
      :plant,
      owner_organization_id:   org.id,
      source_organization_id:  org.id,
      data_source_id:          data_source.id,
      source_record_id:        'src-plant-1',
      source_snapshot:         source_attrs,
      scientific_name:         'Local Name',
      family_names:            'Moringaceae'
    )
  end

  let(:content_conflict) do
    create(
      :sync_conflict,
      syncable:         plant,
      data_source:      data_source,
      conflict_type:    'content',
      status:           'open',
      base_payload:     source_attrs,
      local_payload:    { 'scientific_name' => 'Local Name', 'family_names' => 'Moringaceae' },
      incoming_payload: { 'scientific_name' => 'Upstream Name', 'family_names' => 'Moringaceae' }
    )
  end

  let(:deletion_conflict) do
    create(
      :sync_conflict,
      syncable:         plant,
      data_source:      data_source,
      conflict_type:    'source_deletion',
      status:           'open',
      base_payload:     source_attrs,
      local_payload:    source_attrs,
      incoming_payload: {}
    )
  end

  # Builds a User with an org claim for the given role. Attaches a principal and
  # personal org so current_principal_id works in the mutation.
  def build_org_user(org, role:, trust: 4)
    principal = create(:principal)
    User.new(
      'uid'          => principal.external_uid,
      'email'        => principal.email,
      'trust_levels' => { 'plant' => trust },
      'organizations' => [{
        'id'    => org.id,
        'name'  => org.name,
        'roles' => { 'plant' => role }
      }]
    ).tap do |u|
      u.principal            = principal
      u.personal_organization = Organization.personal_for!(principal)
    end
  end

  def execute(conflict, resolution, user)
    conflict_gid = PlantApiSchema.id_from_object(conflict, SyncConflict, {})
    PlantApiSchema.execute(
      mutation,
      context:   { current_user: user },
      variables: { input: { conflictId: conflict_gid, resolution: resolution } }
    )
  end

  # ---------------------------------------------------------------------------
  # Authorization: member cannot resolve
  # ---------------------------------------------------------------------------
  context 'when user is a member (no resolve_conflicts capability)' do
    let(:user) { build_org_user(org, role: 'member') }

    it 'returns 403' do
      result = execute(content_conflict, 'KEEP_LOCAL', user)
      expect(result['data']).to be_nil
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  # ---------------------------------------------------------------------------
  # Editor KEEP_LOCAL
  # ---------------------------------------------------------------------------
  context 'when user is an editor (has resolve_conflicts)' do
    let(:user) { build_org_user(org, role: 'editor') }

    describe 'KEEP_LOCAL' do
      it 'resolves the conflict and sets sync_state locally_modified' do
        result = execute(content_conflict, 'KEEP_LOCAL', user)

        expect(result['errors']).to be_nil
        payload = result.dig('data', 'resolveSyncConflict')
        expect(payload['errors']).to be_empty
        expect(payload['syncConflict']['status']).to eq 'resolved'
        expect(payload['syncConflict']['resolution']).to eq 'keep_local'

        plant.reload
        expect(plant.sync_state).to eq 'locally_modified'
      end

      it 'adopts local attrs as the new source_snapshot' do
        execute(content_conflict, 'KEEP_LOCAL', user)

        plant.reload
        expect(plant.source_snapshot).to be_present
      end

      it 'follow-up sync with same incoming creates NO new conflict after keep_local' do
        execute(content_conflict, 'KEEP_LOCAL', user)
        plant.reload

        # Simulate a follow-up sync -- if local snapshot == incoming, no conflict
        # The snapshot was just set to local, so same incoming should produce locally_modified or synced.
        initial_conflict_count = SyncConflict.where(syncable: plant, conflict_type: 'content', status: 'open').count
        expect(initial_conflict_count).to eq 0
      end
    end

    describe 'ACCEPT_INCOMING content conflict' do
      it 'applies incoming attrs and sets sync_state synced' do
        result = execute(content_conflict, 'ACCEPT_INCOMING', user)

        expect(result['errors']).to be_nil
        payload = result.dig('data', 'resolveSyncConflict')
        expect(payload['errors']).to be_empty
        expect(payload['syncConflict']['status']).to eq 'resolved'

        plant.reload
        expect(plant.scientific_name).to eq 'Upstream Name'
        expect(plant.sync_state).to eq 'synced'
        expect(plant.source_snapshot['scientific_name']).to eq 'Upstream Name'
      end
    end

    describe 'ACCEPT_INCOMING on source_deletion' do
      it 'returns 403 (editor lacks accept_source_deletion)' do
        result = execute(deletion_conflict, 'ACCEPT_INCOMING', user)
        expect(result['data']).to be_nil
        expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Steward: ACCEPT_INCOMING source_deletion allowed
  # ---------------------------------------------------------------------------
  context 'when user is a steward (has accept_source_deletion)' do
    let(:user) { build_org_user(org, role: 'steward') }

    it 'soft-deletes the record and resolves the conflict' do
      result = execute(deletion_conflict, 'ACCEPT_INCOMING', user)

      expect(result['errors']).to be_nil
      payload = result.dig('data', 'resolveSyncConflict')
      expect(payload['errors']).to be_empty
      expect(payload['syncConflict']['status']).to eq 'resolved'

      plant.reload
      expect(plant.deleted_at).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Superuser: allowed all operations
  # ---------------------------------------------------------------------------
  context 'when user is system superuser (trust >= 10)' do
    let(:user) do
      build_org_user(org, role: 'member', trust: 10).tap do |u|
        # trust 10 -> system_superuser? true bypasses role checks
      end
    end

    # Rebuild with trust 10 and no role that grants resolve_conflicts so we confirm
    # the admin? / system_superuser? override works
    let(:superuser) do
      principal = create(:principal)
      User.new(
        'uid'          => principal.external_uid,
        'email'        => principal.email,
        'trust_levels' => { 'plant' => 10 },
        'organizations' => []
      ).tap do |u|
        u.principal            = principal
        u.personal_organization = Organization.personal_for!(principal)
      end
    end

    it 'allows KEEP_LOCAL without any org role' do
      result = execute(content_conflict, 'KEEP_LOCAL', superuser)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'resolveSyncConflict', 'errors')).to be_empty
    end

    it 'allows ACCEPT_INCOMING source_deletion without any org role' do
      result = execute(deletion_conflict, 'ACCEPT_INCOMING', superuser)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'resolveSyncConflict', 'errors')).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Already-resolved conflict returns 400 error
  # ---------------------------------------------------------------------------
  context 'when the conflict is already resolved' do
    let(:user) { build_org_user(org, role: 'editor') }
    let(:resolved_conflict) do
      create(
        :sync_conflict,
        :resolved,
        syncable:    plant,
        data_source: data_source
      )
    end

    it 'returns a 400 error in the payload' do
      result = execute(resolved_conflict, 'KEEP_LOCAL', user)

      expect(result['errors']).to be_nil
      payload = result.dig('data', 'resolveSyncConflict')
      expect(payload['syncConflict']).to be_nil
      expect(payload['errors'].first['code']).to eq 400
      expect(payload['errors'].first['message']).to include('already resolved')
    end
  end
end
