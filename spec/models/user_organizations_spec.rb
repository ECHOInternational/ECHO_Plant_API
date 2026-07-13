# frozen_string_literal: true

require 'rails_helper'

# Helper: build a User with optional org claims and attached principal/personal org.
def build_user_with_claims(trust_level:, claims: [], principal: nil, personal_org: nil)
  user = User.new(
    'uid' => SecureRandom.uuid,
    'email' => Faker::Internet.unique.email,
    'trust_levels' => { 'plant' => trust_level },
    'organizations' => claims
  )
  user.principal = principal if principal
  user.personal_organization = personal_org if personal_org
  user
end

RSpec.describe User, type: :model do
  describe '#role_in' do
    context 'personal organization' do
      let(:principal) { create(:principal) }
      let(:personal_org) { Organization.personal_for!(principal) }

      it 'returns org_admin when the user can write (trust >= 2)' do
        user = build_user_with_claims(trust_level: 2, principal: principal, personal_org: personal_org)
        expect(user.role_in(personal_org.id)).to eq('org_admin')
      end

      it 'returns org_admin for higher trust levels too (trust 4)' do
        user = build_user_with_claims(trust_level: 4, principal: principal, personal_org: personal_org)
        expect(user.role_in(personal_org.id)).to eq('org_admin')
      end

      it 'returns member when the user is read-only (trust 1)' do
        user = build_user_with_claims(trust_level: 1, principal: principal, personal_org: personal_org)
        expect(user.role_in(personal_org.id)).to eq('member')
      end

      it 'returns member when trust is 0 (no access, but we pass personal org id)' do
        user = build_user_with_claims(trust_level: 0, principal: principal, personal_org: personal_org)
        # can_write? is false, so falls back to member
        expect(user.role_in(personal_org.id)).to eq('member')
      end
    end

    context 'claimed real organization' do
      let(:org) { create(:organization, :real) }

      it 'returns the claimed role when the role is valid' do
        %w[member contributor editor steward org_admin].each do |role|
          user = build_user_with_claims(
            trust_level: 2,
            claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }]
          )
          expect(user.role_in(org.id)).to eq(role)
        end
      end

      it 'returns nil for an unknown role string' do
        user = build_user_with_claims(
          trust_level: 2,
          claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'overlord' } }]
        )
        expect(user.role_in(org.id)).to be_nil
      end

      it 'returns nil for an org not present in claims' do
        other_org_id = SecureRandom.uuid
        user = build_user_with_claims(
          trust_level: 2,
          claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'editor' } }]
        )
        expect(user.role_in(other_org_id)).to be_nil
      end
    end

    it 'returns nil when organization_id is nil' do
      user = build_user_with_claims(trust_level: 2)
      expect(user.role_in(nil)).to be_nil
    end
  end

  describe '#readable_organization_ids' do
    let(:org_a) { create(:organization, :real) }
    let(:org_b) { create(:organization, :real) }
    let(:principal) { create(:principal) }
    let(:personal_org) { Organization.personal_for!(principal) }

    it 'includes personal org id when personal_organization is set' do
      user = build_user_with_claims(trust_level: 2, principal: principal, personal_org: personal_org)
      expect(user.readable_organization_ids).to include(personal_org.id)
    end

    it 'includes claimed org ids with valid roles' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [
          { 'id' => org_a.id, 'name' => org_a.name, 'roles' => { 'plant' => 'editor' } },
          { 'id' => org_b.id, 'name' => org_b.name, 'roles' => { 'plant' => 'member' } }
        ],
        principal: principal,
        personal_org: personal_org
      )
      ids = user.readable_organization_ids
      expect(ids).to include(org_a.id)
      expect(ids).to include(org_b.id)
    end

    it 'ignores claims with invalid role strings' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org_a.id, 'name' => org_a.name, 'roles' => { 'plant' => 'boss' } }],
        principal: principal,
        personal_org: personal_org
      )
      expect(user.readable_organization_ids).not_to include(org_a.id)
    end

    it 'returns only the personal org id when there are no claims' do
      user = build_user_with_claims(trust_level: 2, principal: principal, personal_org: personal_org)
      expect(user.readable_organization_ids).to eq([personal_org.id])
    end

    it 'returns empty array when no principal and no claims' do
      user = build_user_with_claims(trust_level: 2)
      expect(user.readable_organization_ids).to be_empty
    end

    it 'returns empty array when principal is nil (anonymous-like user)' do
      user = build_user_with_claims(trust_level: 2)
      # no personal_organization set
      expect(user.readable_organization_ids).to be_empty
    end
  end

  describe '#can_create_in_any_organization?' do
    let(:org) { create(:organization, :real) }

    it 'returns true for contributor in a real org' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'contributor' } }]
      )
      expect(user.can_create_in_any_organization?).to be true
    end

    it 'returns true for editor in a real org' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'editor' } }]
      )
      expect(user.can_create_in_any_organization?).to be true
    end

    it 'returns true for steward in a real org' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'steward' } }]
      )
      expect(user.can_create_in_any_organization?).to be true
    end

    it 'returns true for org_admin in a real org' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'org_admin' } }]
      )
      expect(user.can_create_in_any_organization?).to be true
    end

    it 'returns false for member (member lacks :create capability)' do
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'member' } }]
      )
      expect(user.can_create_in_any_organization?).to be false
    end

    it 'returns false when there are no claims (personal org excluded)' do
      principal = create(:principal)
      personal_org = Organization.personal_for!(principal)
      user = build_user_with_claims(trust_level: 2, principal: principal, personal_org: personal_org)
      # personal org is excluded by design -- only real orgs count here
      expect(user.can_create_in_any_organization?).to be false
    end

    it 'returns false with no claims at all' do
      user = build_user_with_claims(trust_level: 2)
      expect(user.can_create_in_any_organization?).to be false
    end
  end

  describe '#created_record?' do
    let(:principal) { create(:principal) }

    it "returns true when the record's created_by_principal_id matches the principal" do
      user   = build_user_with_claims(trust_level: 2, principal: principal)
      record = build(:plant, created_by_principal_id: principal.id)
      expect(user.created_record?(record)).to be true
    end

    it "returns false when the record's created_by_principal_id is a different principal" do
      other  = create(:principal)
      user   = build_user_with_claims(trust_level: 2, principal: principal)
      record = build(:plant, created_by_principal_id: other.id)
      expect(user.created_record?(record)).to be false
    end

    it "returns false when the record's created_by_principal_id is nil" do
      user   = build_user_with_claims(trust_level: 2, principal: principal)
      record = build(:plant, created_by_principal_id: nil)
      expect(user.created_record?(record)).to be false
    end

    # BUG: created_record? returns nil (not false) when user.principal is nil
    # because the expression is `principal && ...` and short-circuits to nil.
    # The method should return false for any falsey result to avoid surprising
    # truthy/nil confusion in callers. See app/models/user.rb #created_record?.
    it 'returns false when user has no principal' do
      pending 'BUG app/models/user.rb: created_record? returns nil instead of false ' \
              'when principal is nil (short-circuit of &&-chain)'
      user   = build_user_with_claims(trust_level: 2)
      record = build(:plant, created_by_principal_id: SecureRandom.uuid)
      expect(user.created_record?(record)).to be false
    end

    it 'returns false when record does not respond to created_by_principal_id' do
      user   = build_user_with_claims(trust_level: 2, principal: principal)
      record = double('UnknownRecord')
      allow(record).to receive(:respond_to?).with(:created_by_principal_id).and_return(false)
      expect(user.created_record?(record)).to be false
    end
  end

  describe '#reads_owned_record?' do
    let(:principal) { create(:principal) }

    it "returns true when the record is owned by the user's email (legacy)" do
      user   = build_user_with_claims(trust_level: 2, principal: principal)
      record = build(:plant, :private, owned_by: user.email)
      expect(user.reads_owned_record?(record)).to be true
    end

    it "returns true when the record's owner_organization_id is in readable_organization_ids" do
      org          = create(:organization, :real)
      personal_org = Organization.personal_for!(principal)
      user = build_user_with_claims(
        trust_level: 2,
        claims: [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'member' } }],
        principal: principal,
        personal_org: personal_org
      )
      record = build(:plant, :private, owned_by: 'someoneelse@example.org',
                                       owner_organization_id: org.id)
      expect(user.reads_owned_record?(record)).to be true
    end

    it 'returns false when neither email nor org matches' do
      personal_org = Organization.personal_for!(principal)
      user = build_user_with_claims(trust_level: 2, principal: principal, personal_org: personal_org)
      record = build(:plant, :private, owned_by: 'other@example.org',
                                       owner_organization_id: SecureRandom.uuid)
      expect(user.reads_owned_record?(record)).to be false
    end
  end
end
