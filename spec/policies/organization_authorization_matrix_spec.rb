# frozen_string_literal: true

require 'rails_helper'

# ---------------------------------------------------------------------------
# Shared actor builder
# ---------------------------------------------------------------------------
#
# Builds an in-memory User with the given trust level and optional org claims,
# then attaches a persisted Principal and personal Organization so that the
# org-branch logic fires correctly.
#
def actor_for(trust_level:, claims: [])
  principal    = create(:principal)
  personal_org = Organization.personal_for!(principal)
  User.new(
    'uid' => principal.external_uid,
    'email' => principal.email,
    'trust_levels' => { 'plant' => trust_level },
    'organizations' => claims
  ).tap do |u|
    u.principal = principal
    u.personal_organization = personal_org
  end
end

# ---------------------------------------------------------------------------
# Helper: org claim hash
# ---------------------------------------------------------------------------
def claim_for(org, role)
  { 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }
end

# ---------------------------------------------------------------------------
# Shared examples: parameterised per independently-owned model
# ---------------------------------------------------------------------------
RSpec.shared_examples 'organization authorization matrix' do |factory_name, policy_class|
  let(:org) { create(:organization, :real) }
  let(:org_b) { create(:organization, :real) }

  # Record owned by org; owned_by email is a third-party address so the
  # legacy email branch never fires for any of our test actors.
  let(:record) do
    create(factory_name, :private,
           owned_by: 'legacy-owner@example.org',
           owner_organization_id: org.id,
           source_organization_id: org.id)
  end

  # -------------------------------------------------------------------------
  # Helpers that build actors with specific org roles
  # -------------------------------------------------------------------------
  def actor_with_role(org, role, trust: 2)
    principal    = create(:principal)
    personal_org = Organization.personal_for!(principal)
    User.new(
      'uid' => principal.external_uid,
      'email' => principal.email,
      'trust_levels' => { 'plant' => trust },
      'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }]
    ).tap do |u|
      u.principal = principal
      u.personal_organization = personal_org
    end
  end

  def contributor_creator(org, record)
    principal    = create(:principal)
    personal_org = Organization.personal_for!(principal)
    record.update!(created_by_principal_id: principal.id)
    User.new(
      'uid' => principal.external_uid,
      'email' => principal.email,
      'trust_levels' => { 'plant' => 2 },
      'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'contributor' } }]
    ).tap do |u|
      u.principal = principal
      u.personal_organization = personal_org
    end
  end

  def contributor_non_creator(org)
    actor_with_role(org, 'contributor')
  end

  # -------------------------------------------------------------------------
  # MEMBER
  # -------------------------------------------------------------------------
  describe 'member' do
    subject(:policy) { policy_class.new(actor_with_role(org, 'member'), record) }

    it 'can show? a private org record' do
      expect(policy.show?).to be true
    end

    it 'cannot update? the record' do
      expect(policy.update?).to be false
    end

    it 'cannot soft_delete?' do
      expect(policy.soft_delete?).to be false
    end

    it 'cannot restore?' do
      expect(policy.restore?).to be false
    end

    it 'cannot destroy?' do
      expect(policy.destroy?).to be false
    end

    # create? at class-level: trust-2 member still passes via legacy can_write?
    it 'can create? (trust-2 user with member claim passes via can_write?)' do
      # NOTE: create? is class-level. For trust-2 users can_write? is true,
      # so create? returns true regardless of org role. The capability
      # distinction (contributor+ required) only matters for trust-1 users.
      policy_class_level = policy_class.new(actor_with_role(org, 'member', trust: 2), Plant)
      expect(policy_class_level.create?).to be true
    end
  end

  # create? with low trust (trust-1): org role matters
  describe 'create? with trust-1 user' do
    it 'is true when the user has contributor claim (can_create_in_any_organization?)' do
      actor = actor_with_role(org, 'contributor', trust: 1)
      policy = policy_class.new(actor, Plant)
      expect(policy.create?).to be true
    end

    it 'is false when the user has only member claim and trust-1 (neither can_write? nor contributor+)' do
      actor = actor_with_role(org, 'member', trust: 1)
      policy = policy_class.new(actor, Plant)
      expect(policy.create?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # CONTRIBUTOR
  # -------------------------------------------------------------------------
  describe 'contributor (creator of the record)' do
    it 'can update?' do
      actor = contributor_creator(org, record)
      expect(policy_class.new(actor, record).update?).to be true
    end

    it 'cannot soft_delete? even on records they created' do
      actor = contributor_creator(org, record)
      expect(policy_class.new(actor, record).soft_delete?).to be false
    end

    it 'cannot restore?' do
      actor = contributor_creator(org, record)
      expect(policy_class.new(actor, record).restore?).to be false
    end
  end

  describe 'contributor (NOT the creator)' do
    it 'cannot update?' do
      actor = contributor_non_creator(org)
      expect(policy_class.new(actor, record).update?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # EDITOR
  # -------------------------------------------------------------------------
  describe 'editor' do
    subject(:policy) { policy_class.new(actor_with_role(org, 'editor'), record) }

    it 'can update? any org record' do
      expect(policy.update?).to be true
    end

    it 'cannot soft_delete?' do
      expect(policy.soft_delete?).to be false
    end

    it 'cannot restore?' do
      expect(policy.restore?).to be false
    end

    it 'cannot destroy?' do
      expect(policy.destroy?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # STEWARD
  # -------------------------------------------------------------------------
  describe 'steward' do
    subject(:policy) { policy_class.new(actor_with_role(org, 'steward'), record) }

    it 'can update?' do
      expect(policy.update?).to be true
    end

    it 'can soft_delete?' do
      expect(policy.soft_delete?).to be true
    end

    it 'can restore?' do
      expect(policy.restore?).to be true
    end

    it 'cannot destroy? (hard delete stays superuser/legacy-owner only)' do
      expect(policy.destroy?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # ORG_ADMIN
  # -------------------------------------------------------------------------
  describe 'org_admin' do
    subject(:policy) { policy_class.new(actor_with_role(org, 'org_admin'), record) }

    it 'can update?' do
      expect(policy.update?).to be true
    end

    it 'can soft_delete?' do
      expect(policy.soft_delete?).to be true
    end

    it 'can restore?' do
      expect(policy.restore?).to be true
    end

    it 'cannot destroy? (no hard-delete hook for org_admin yet)' do
      expect(policy.destroy?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # SYSTEM SUPERUSER (trust 10, no claims)
  # -------------------------------------------------------------------------
  describe 'system superuser (trust 10, no org claims)' do
    let(:superuser) do
      principal    = create(:principal)
      personal_org = Organization.personal_for!(principal)
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 10 },
        'organizations' => []
      ).tap do |u|
        u.principal = principal
        u.personal_organization = personal_org
      end
    end

    subject(:policy) { policy_class.new(superuser, record) }

    it 'can update?' do
      expect(policy.update?).to be true
    end

    it 'can soft_delete?' do
      expect(policy.soft_delete?).to be true
    end

    it 'can restore?' do
      expect(policy.restore?).to be true
    end

    it 'can destroy?' do
      expect(policy.destroy?).to be true
    end
  end

  # -------------------------------------------------------------------------
  # NO MEMBERSHIP IN OWNING ORG
  # -------------------------------------------------------------------------
  describe 'user with NO membership in the owning org' do
    let(:outsider) do
      principal    = create(:principal)
      personal_org = Organization.personal_for!(principal)
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

    subject(:policy) { policy_class.new(outsider, record) }

    it 'cannot show? a private record' do
      expect(policy.show?).to be false
    end

    it 'cannot update?' do
      expect(policy.update?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # SOURCE-ORG-ONLY MEMBERSHIP GRANTS NOTHING
  # -------------------------------------------------------------------------
  describe 'source-org-only membership grants nothing on owner-org records' do
    let(:source_org_record) do
      create(factory_name, :private,
             owned_by: 'legacy-owner@example.org',
             owner_organization_id: org.id,
             source_organization_id: org_b.id)
    end

    it 'org_admin of source org cannot show? private record owned by a different org' do
      admin_of_source = actor_with_role(org_b, 'org_admin')
      policy = policy_class.new(admin_of_source, source_org_record)
      expect(policy.show?).to be false
    end

    it 'org_admin of source org cannot update? the record' do
      admin_of_source = actor_with_role(org_b, 'org_admin')
      policy = policy_class.new(admin_of_source, source_org_record)
      expect(policy.update?).to be false
    end

    it 'org_admin of source org cannot soft_delete? the record' do
      admin_of_source = actor_with_role(org_b, 'org_admin')
      policy = policy_class.new(admin_of_source, source_org_record)
      expect(policy.soft_delete?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # REVOKED MEMBERSHIP (claim absent)
  # -------------------------------------------------------------------------
  describe 'revoked membership (org id absent from claims)' do
    let(:revoked_user) do
      # User has no claim for org at all -- simulates token after revocation
      actor_with_role(org_b, 'editor') # claim for a different org only
    end

    it 'cannot show? the private org record' do
      policy = policy_class.new(revoked_user, record)
      expect(policy.show?).to be false
    end

    it 'cannot update?' do
      policy = policy_class.new(revoked_user, record)
      expect(policy.update?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # MULTIPLE ORGS: right org grants, wrong org denies
  # -------------------------------------------------------------------------
  describe 'actor with editor in orgA and member in orgB' do
    let(:record_b) do
      create(factory_name, :private,
             owned_by: 'other-owner@example.org',
             owner_organization_id: org_b.id,
             source_organization_id: org_b.id)
    end

    let(:multi_org_actor) do
      principal    = create(:principal)
      personal_org = Organization.personal_for!(principal)
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [
          { 'id' => org.id,   'name' => org.name,   'roles' => { 'plant' => 'editor' } },
          { 'id' => org_b.id, 'name' => org_b.name, 'roles' => { 'plant' => 'member' } }
        ]
      ).tap do |u|
        u.principal = principal
        u.personal_organization = personal_org
      end
    end

    it 'can update? a record in orgA (editor)' do
      expect(policy_class.new(multi_org_actor, record).update?).to be true
    end

    it 'cannot update? a record in orgB (member)' do
      expect(policy_class.new(multi_org_actor, record_b).update?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # SCOPE: tenant leakage
  # -------------------------------------------------------------------------
  describe 'Pundit scope tenant leakage' do
    let(:member_actor) { actor_with_role(org, 'member') }
    let(:other_org) { create(:organization, :real) }

    let!(:org_private_record) do
      create(factory_name, :private,
             owned_by: 'org-owner@example.org',
             owner_organization_id: org.id)
    end
    let!(:other_org_private_record) do
      create(factory_name, :private,
             owned_by: 'other@example.org',
             owner_organization_id: other_org.id)
    end
    let!(:legacy_private_record) do
      create(factory_name, :private,
             owned_by: 'third@example.org',
             owner_organization_id: nil)
    end
    let!(:public_record) do
      create(factory_name, :public,
             owned_by: 'anyone@example.org',
             owner_organization_id: nil)
    end

    let(:model_class) do
      factory_name.to_s.camelize.constantize
    end

    it "returns org's own private records in the scope" do
      scope = Pundit.policy_scope(member_actor, model_class)
      expect(scope.to_a).to include(org_private_record)
    end

    it "does NOT return the other org's private records" do
      scope = Pundit.policy_scope(member_actor, model_class)
      expect(scope.to_a).not_to include(other_org_private_record)
    end

    it "does NOT return legacy private records (NULL owner_organization_id) that the user doesn't email-own" do
      scope = Pundit.policy_scope(member_actor, model_class)
      expect(scope.to_a).not_to include(legacy_private_record)
    end

    it 'returns public records' do
      scope = Pundit.policy_scope(member_actor, model_class)
      expect(scope.to_a).to include(public_record)
    end

    it 'anonymous scope returns only public records' do
      scope = Pundit.policy_scope(nil, model_class)
      expect(scope.to_a).to include(public_record)
      expect(scope.to_a).not_to include(org_private_record)
      expect(scope.to_a).not_to include(other_org_private_record)
      expect(scope.to_a).not_to include(legacy_private_record)
    end
  end
end

# ---------------------------------------------------------------------------
# Apply shared examples for each independently-owned model
# ---------------------------------------------------------------------------
RSpec.describe PlantPolicy, type: :policy do
  include_examples 'organization authorization matrix', :plant, PlantPolicy
end

RSpec.describe VarietyPolicy, type: :policy do
  include_examples 'organization authorization matrix', :variety, VarietyPolicy
end

RSpec.describe SpecimenPolicy, type: :policy do
  include_examples 'organization authorization matrix', :specimen, SpecimenPolicy
end

RSpec.describe LocationPolicy, type: :policy do
  include_examples 'organization authorization matrix', :location, LocationPolicy
end

RSpec.describe CategoryPolicy, type: :policy do
  include_examples 'organization authorization matrix', :category, CategoryPolicy
end
