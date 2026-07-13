# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Me Query', type: :graphql_query do
  let(:query_string) do
    <<~GRAPHQL
      query {
        me {
          email
          displayName
          principalId
          organizations {
            organization { id kind name }
            role
          }
        }
      }
    GRAPHQL
  end

  def execute(user)
    PlantApiSchema.execute(query_string, context: { current_user: user })
  end

  context 'when anonymous (no current_user)' do
    it 'returns null for me' do
      result = execute(nil)
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'me')).to be_nil
    end
  end

  context 'when authenticated with a resolved principal' do
    let(:principal) { create(:principal) }
    let(:personal_org) { Organization.personal_for!(principal) }
    let(:user) do
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => []
      ).tap do |u|
        u.principal = principal
        u.personal_organization = personal_org
      end
    end

    it 'returns the user email' do
      result = execute(user)
      expect(result['errors']).to be_nil
      me = result.dig('data', 'me')
      expect(me['email']).to eq user.email
    end

    it 'returns the display_name from the principal' do
      result = execute(user)
      me = result.dig('data', 'me')
      expect(me['displayName']).to eq principal.display_name
    end

    it 'returns a principalId relay global ID' do
      result = execute(user)
      me = result.dig('data', 'me')
      expect(me['principalId']).to be_present
      # Should decode to the principal's id
      _type, raw_id = GraphQL::Schema::UniqueWithinType.decode(me['principalId'])
      expect(raw_id).to eq principal.id
    end

    it 'includes the personal organization in organizations' do
      result = execute(user)
      me = result.dig('data', 'me')
      orgs = me['organizations']
      expect(orgs).not_to be_empty
      personal_entry = orgs.find { |o| o.dig('organization', 'kind') == 'personal' }
      expect(personal_entry).not_to be_nil
      expect(personal_entry['role']).to eq 'org_admin'
    end

    context 'with real org memberships in the JWT' do
      let(:real_org) { create(:organization, :real) }
      # Test convention (matching visibility_transition_gates_spec): claim 'id'
      # is the local organization UUID (org.id), which is what owner_organization_id
      # stores and what role_in resolves against.
      let(:user) do
        User.new(
          'uid' => principal.external_uid,
          'email' => principal.email,
          'trust_levels' => { 'plant' => 2 },
          'organizations' => [
            { 'id' => real_org.id, 'name' => real_org.name, 'roles' => { 'plant' => 'editor' } }
          ]
        ).tap do |u|
          u.principal = principal
          u.personal_organization = personal_org
        end
      end

      it 'includes the real org in organizations with the correct role' do
        result = execute(user)
        orgs = result.dig('data', 'me', 'organizations')
        real_entry = orgs.find { |o| o.dig('organization', 'kind') == 'real' }
        expect(real_entry).not_to be_nil
        expect(real_entry['role']).to eq 'editor'
      end

      it 'skips organizations whose mirror row is missing' do
        # Create a claim for an org that has no local mirror row
        nonexistent_id = SecureRandom.uuid
        user_with_missing_org = User.new(
          'uid' => principal.external_uid,
          'email' => principal.email,
          'trust_levels' => { 'plant' => 2 },
          'organizations' => [
            { 'id' => nonexistent_id, 'name' => 'Missing Org', 'roles' => { 'plant' => 'editor' } }
          ]
        ).tap do |u|
          u.principal = principal
          u.personal_organization = personal_org
        end
        result = execute(user_with_missing_org)
        orgs = result.dig('data', 'me', 'organizations')
        # Should not raise; org with no local mirror row is silently skipped
        real_entries = orgs.select { |o| o.dig('organization', 'kind') == 'real' }
        expect(real_entries).to be_empty
      end
    end
  end
end
