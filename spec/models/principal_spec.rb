# frozen_string_literal: true

require "rails_helper"

RSpec.describe Principal, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:principal)).to be_valid
    end

    it "is not valid without identity_issuer" do
      expect(build(:principal, identity_issuer: nil)).not_to be_valid
    end

    it "is not valid without email" do
      expect(build(:principal, email: nil)).not_to be_valid
    end

    it "is not valid without kind" do
      expect(build(:principal, kind: nil)).not_to be_valid
    end

    it "is not valid with an unknown kind" do
      expect(build(:principal, kind: "robot")).not_to be_valid
    end

    it "is valid as a service principal" do
      expect(build(:principal, :service)).to be_valid
    end
  end

  describe "associations" do
    it "can have a personal organization" do
      principal = create(:principal)
      org = create(:organization, :personal, principal: principal)
      expect(principal.personal_organization).to eq org
    end
  end

  describe ".resolve!" do
    let(:issuer) { "https://www.echocommunity.org" }
    let(:uid)    { SecureRandom.uuid }
    let(:email)  { "user@example.com" }

    context "when principal does not exist" do
      it "creates a new principal" do
        expect {
          described_class.resolve!(issuer: issuer, external_uid: uid, email: email)
        }.to change(Principal, :count).by(1)
      end

      it "sets provided attributes" do
        principal = described_class.resolve!(
          issuer: issuer, external_uid: uid,
          email: email, display_name: "Alice"
        )
        expect(principal.email).to eq email
        expect(principal.display_name).to eq "Alice"
        expect(principal.kind).to eq "human"
      end
    end

    context "when principal already exists" do
      let!(:existing) do
        create(:principal, identity_issuer: issuer, external_uid: uid,
               email: "old@example.com", last_authenticated_at: 2.hours.ago)
      end

      it "does not create a duplicate" do
        expect {
          described_class.resolve!(issuer: issuer, external_uid: uid, email: email)
        }.not_to change(Principal, :count)
      end

      it "updates stale email" do
        described_class.resolve!(issuer: issuer, external_uid: uid, email: email)
        expect(existing.reload.email).to eq email
      end

      it "updates last_authenticated_at when stale" do
        before_call = Time.current
        described_class.resolve!(issuer: issuer, external_uid: uid, email: email)
        expect(existing.reload.last_authenticated_at).to be >= before_call
      end

      it "does not update last_authenticated_at when fresh" do
        existing.update!(last_authenticated_at: 30.minutes.ago)
        original_auth = existing.reload.last_authenticated_at.to_i
        described_class.resolve!(issuer: issuer, external_uid: uid, email: existing.email)
        expect(existing.reload.last_authenticated_at.to_i).to eq original_auth
      end
    end

    context "RecordNotUnique race condition" do
      it "falls back to find when create races" do
        existing = create(:principal, identity_issuer: issuer, external_uid: uid,
                          email: email)
        allow(Principal).to receive(:find_by)
          .with(identity_issuer: issuer, external_uid: uid)
          .and_return(nil, existing)
        allow(Principal).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
        allow(Principal).to receive(:find_by!)
          .with(identity_issuer: issuer, external_uid: uid)
          .and_return(existing)

        result = described_class.resolve!(issuer: issuer, external_uid: uid, email: email)
        expect(result).to eq existing
      end
    end
  end

  describe ".legacy_for_email" do
    let(:email) { "legacy@example.com" }

    it "creates a legacy principal" do
      principal = described_class.legacy_for_email(email)
      expect(principal).to be_persisted
      expect(principal.identity_issuer).to eq Principal::LEGACY_ISSUER
      expect(principal.external_uid).to be_nil
      expect(principal.kind).to eq "human"
    end

    it "is idempotent" do
      p1 = described_class.legacy_for_email(email)
      p2 = described_class.legacy_for_email(email)
      expect(p1.id).to eq p2.id
    end
  end
end
