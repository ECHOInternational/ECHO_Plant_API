# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Principal identity lifecycle', type: :model do
  let(:issuer)    { 'https://www.echocommunity.org' }
  let(:uid)       { SecureRandom.uuid }
  let(:email_v1)  { 'alice.v1@example.org' }
  let(:email_v2)  { 'alice.v2@example.org' } # simulates an IdP email change

  # -------------------------------------------------------------------------
  # Same (issuer, uid) with a new email resolves to the SAME principal
  # -------------------------------------------------------------------------
  describe 'email update does not orphan authorization' do
    let!(:principal) do
      Principal.resolve!(issuer: issuer, external_uid: uid, email: email_v1,
                         display_name: 'Alice V1')
    end

    let!(:org) { create(:organization, :real) }

    let(:record) do
      create(:plant, :private,
             owned_by: email_v1,
             owner_organization_id: org.id,
             created_by_principal_id: principal.id)
    end

    it 'resolves to the same principal row after email change' do
      refreshed = Principal.resolve!(issuer: issuer, external_uid: uid, email: email_v2)
      expect(refreshed.id).to eq(principal.id)
    end

    it 'updates the principal email in place' do
      Principal.resolve!(issuer: issuer, external_uid: uid, email: email_v2)
      expect(principal.reload.email).to eq(email_v2)
    end

    it 'access via the org branch (created_by_principal_id) still works after email change' do
      # Rebuild user with new email; the principal is still the same row
      new_email_user = User.new(
        'uid' => uid,
        'email' => email_v2,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'contributor' } }]
      ).tap do |u|
        personal_org = Organization.personal_for!(principal)
        u.principal = principal
        u.personal_organization = personal_org
      end

      # created_record? must pass (principal id unchanged)
      expect(new_email_user.created_record?(record)).to be true
      # Policy update? must pass via org contributor + created_by_principal_id
      expect(PlantPolicy.new(new_email_user, record).update?).to be true
    end

    it 'the legacy email branch no longer matches after email change' do
      # After the email change the stored owned_by (email_v1) no longer matches
      # the user's current email (email_v2). Legacy branch fails.
      new_email_user = User.new(
        'uid' => uid,
        'email' => email_v2,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => []
      ).tap do |u|
        personal_org = Organization.personal_for!(principal)
        u.principal = principal
        u.personal_organization = personal_org
      end

      # Legacy owned_by check fails: email_v2 != email_v1
      expect(new_email_user.email).not_to eq(record.owned_by)
    end
  end

  # -------------------------------------------------------------------------
  # Different uid with the SAME email creates a DIFFERENT principal
  # -------------------------------------------------------------------------
  describe 'different uid, same email => distinct principals' do
    let(:uid_a) { SecureRandom.uuid }
    let(:uid_b) { SecureRandom.uuid }
    let(:shared_email) { 'shared@example.org' }

    let!(:principal_a) do
      Principal.resolve!(issuer: issuer, external_uid: uid_a, email: shared_email)
    end

    let!(:principal_b) do
      Principal.resolve!(issuer: issuer, external_uid: uid_b, email: shared_email)
    end

    it 'creates two distinct principal rows' do
      expect(principal_a.id).not_to eq(principal_b.id)
    end

    it "the second principal does NOT inherit the first principal's created records via principal id" do
      org = create(:organization, :real)
      # owned_by is a third-party address so the legacy email branch never
      # accidentally fires for either principal_b or principal_a.
      record_of_a = create(:plant, :private,
                           owned_by: 'legacy-record-owner@example.org',
                           owner_organization_id: org.id,
                           created_by_principal_id: principal_a.id)

      user_b = User.new(
        'uid' => uid_b,
        'email' => shared_email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'contributor' } }]
      ).tap do |u|
        personal_org = Organization.personal_for!(principal_b)
        u.principal = principal_b
        u.personal_organization = personal_org
      end

      # created_record? checks principal.id; principal_b != principal_a
      expect(user_b.created_record?(record_of_a)).to be false
      # contributor's update_own capability requires created_record?; it fails
      # so update? must return false
      expect(PlantPolicy.new(user_b, record_of_a).update?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # Uniqueness: (issuer, uid)
  # -------------------------------------------------------------------------
  describe 'uniqueness constraint on (identity_issuer, external_uid)' do
    it 'raises when a duplicate (issuer, uid) is inserted directly' do
      create(:principal, identity_issuer: issuer, external_uid: uid)
      expect {
        create(:principal, identity_issuer: issuer, external_uid: uid)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows same uid under a different issuer' do
      create(:principal, identity_issuer: issuer, external_uid: uid)
      expect {
        create(:principal, identity_issuer: 'https://other-idp.example.org', external_uid: uid)
      }.not_to raise_error
    end
  end

  # -------------------------------------------------------------------------
  # Legacy principals never collide with JWT principals
  # -------------------------------------------------------------------------
  describe 'legacy_for_email vs JWT principals' do
    let(:email) { 'legacy-and-jwt@example.org' }

    it 'legacy principal has nil external_uid and legacy issuer' do
      legacy = Principal.legacy_for_email(email)
      expect(legacy.external_uid).to be_nil
      expect(legacy.identity_issuer).to eq(Principal::LEGACY_ISSUER)
    end

    it 'does NOT collide with a JWT principal sharing the same email' do
      legacy = Principal.legacy_for_email(email)
      jwt    = Principal.resolve!(issuer: issuer, external_uid: uid, email: email)
      expect(legacy.id).not_to eq(jwt.id)
    end

    it 'multiple legacy_for_email calls are idempotent' do
      p1 = Principal.legacy_for_email(email)
      p2 = Principal.legacy_for_email(email)
      expect(p1.id).to eq(p2.id)
    end

    it 'legacy principals do not collide with each other for different emails' do
      p1 = Principal.legacy_for_email('legacy-a@example.org')
      p2 = Principal.legacy_for_email('legacy-b@example.org')
      expect(p1.id).not_to eq(p2.id)
    end
  end
end
