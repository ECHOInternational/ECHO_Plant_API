# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization, type: :model do
  describe "validations" do
    describe "real organization" do
      subject { build(:organization, :real) }

      it "is not valid without a name" do
        expect(build(:organization, :real, name: nil)).not_to be_valid
      end

      it "is valid with external_idp_id and no principal" do
        expect(subject).to be_valid
      end

      it "is invalid without external_idp_id" do
        subject.external_idp_id = nil
        expect(subject).not_to be_valid
      end

      it "is invalid with a principal_id" do
        subject.principal_id = SecureRandom.uuid
        expect(subject).not_to be_valid
      end
    end

    describe "personal organization" do
      subject { build(:organization, :personal) }

      it "is valid with a principal and no external_idp_id" do
        expect(subject).to be_valid
      end

      it "is invalid without a principal" do
        subject.principal = nil
        expect(subject).not_to be_valid
      end

      it "is invalid with an external_idp_id" do
        subject.external_idp_id = SecureRandom.uuid
        expect(subject).not_to be_valid
      end
    end
  end

  describe ".personal_for!" do
    let(:principal) { create(:principal) }

    it "creates a personal org for the principal" do
      org = described_class.personal_for!(principal)
      expect(org).to be_persisted
      expect(org.kind).to eq "personal"
      expect(org.principal_id).to eq principal.id
    end

    it "uses display_name as name when present" do
      principal.update!(display_name: "Alice Smith")
      org = described_class.personal_for!(principal)
      expect(org.name).to eq "Alice Smith"
    end

    it "falls back to email when display_name is blank" do
      principal.update!(display_name: nil)
      org = described_class.personal_for!(principal)
      expect(org.name).to eq principal.email
    end

    it "is idempotent" do
      o1 = described_class.personal_for!(principal)
      o2 = described_class.personal_for!(principal)
      expect(o1.id).to eq o2.id
    end
  end

  describe ".mirror_real!" do
    let(:ext_id) { SecureRandom.uuid }

    it "creates a new real org" do
      org = described_class.mirror_real!(external_id: ext_id, name: "ECHO")
      expect(org).to be_persisted
      expect(org.kind).to eq "real"
      expect(org.external_idp_id).to eq ext_id
    end

    # Regression: JWT claims carry the IdP org UUID and capability checks
    # compare claim ids against records' owner_organization_id. The mirrored
    # org must therefore adopt the IdP UUID as its LOCAL primary key; a
    # generated local id would make every claim-vs-record comparison fail in
    # production (while passing in specs that conflate the two id spaces).
    it "adopts the IdP UUID as the local primary key" do
      org = described_class.mirror_real!(external_id: ext_id, name: "ECHO")
      expect(org.id).to eq ext_id
    end

    it "grants claim-based capabilities on records owned by a mirrored org" do
      org = described_class.mirror_real!(external_id: ext_id, name: "ECHO")
      user = User.new(
        'uid' => SecureRandom.uuid, 'email' => 'staff@example.org',
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => ext_id, 'name' => 'ECHO',
                              'roles' => { 'plant' => 'editor' } }]
      )
      record = create(:plant, owner_organization_id: org.id,
                              owned_by: 'someoneelse@example.org')
      expect(OwnedResourcePolicy.new(user, record).update?).to be true
    end

    it "is idempotent" do
      o1 = described_class.mirror_real!(external_id: ext_id, name: "ECHO")
      o2 = described_class.mirror_real!(external_id: ext_id, name: "ECHO")
      expect(o1.id).to eq o2.id
    end

    it "refreshes the name when changed" do
      described_class.mirror_real!(external_id: ext_id, name: "Old Name")
      org = described_class.mirror_real!(external_id: ext_id, name: "New Name")
      expect(org.name).to eq "New Name"
    end
  end
end
