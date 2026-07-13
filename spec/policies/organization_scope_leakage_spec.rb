# frozen_string_literal: true

require 'rails_helper'

# Helper: actor with real-org membership
def org_member_actor(org, role: 'member')
  principal    = create(:principal)
  personal_org = Organization.personal_for!(principal)
  User.new(
    'uid' => principal.external_uid,
    'email' => principal.email,
    'trust_levels' => { 'plant' => 2 },
    'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => role } }]
  ).tap do |u|
    u.principal = principal
    u.personal_organization = personal_org
  end
end

RSpec.describe ImagePolicy, type: :policy do
  describe 'Scope - tenant leakage' do
    let(:org)       { create(:organization, :real) }
    let(:other_org) { create(:organization, :real) }
    let(:actor)     { org_member_actor(org) }

    # Org-owned plant and its image
    let(:org_plant) { create(:plant, :private, owned_by: 'owner@example.org', owner_organization_id: org.id) }
    let!(:org_plant_image) { create(:image, :private, imageable: org_plant, owned_by: 'uploader@example.org') }

    # Other-org plant and its image
    let(:other_plant)      { create(:plant, :private, owned_by: 'other@example.org', owner_organization_id: other_org.id) }
    let!(:other_image)     { create(:image, :private, imageable: other_plant, owned_by: 'other-uploader@example.org') }

    # Org-owned specimen and a life-cycle event attached to it
    # Using :harvest_event (an STI subclass) because the base :life_cycle_event
    # factory does not set the required STI `type` column.
    let(:org_specimen)    { create(:specimen, :private, owned_by: 'owner@example.org', owner_organization_id: org.id) }
    let(:org_event)       { create(:harvest_event, specimen: org_specimen) }
    let!(:event_image)    { create(:image, :private, imageable: org_event, owned_by: 'uploader@example.org') }

    # Other-org specimen event image
    let(:other_specimen)  { create(:specimen, :private, owned_by: 'other@example.org', owner_organization_id: other_org.id) }
    let(:other_event)     { create(:harvest_event, specimen: other_specimen) }
    let!(:other_event_image) { create(:image, :private, imageable: other_event, owned_by: 'uploader@example.org') }

    # Legacy (NULL owner_organization_id) plant image
    let(:legacy_plant)    { create(:plant, :private, owned_by: 'legacy@example.org', owner_organization_id: nil) }
    let!(:legacy_image)   { create(:image, :private, imageable: legacy_plant, owned_by: 'legacy@example.org') }

    let(:scope) { Pundit.policy_scope(actor, Image) }

    it 'includes images attached to org-owned plants' do
      expect(scope.to_a).to include(org_plant_image)
    end

    it 'includes images attached to life-cycle events of org-owned specimens' do
      expect(scope.to_a).to include(event_image)
    end

    it "does NOT include images of other org's private plants" do
      expect(scope.to_a).not_to include(other_image)
    end

    it "does NOT include images of other org's life-cycle events" do
      expect(scope.to_a).not_to include(other_event_image)
    end

    it 'does NOT include images of legacy (null org) private plants the user does not email-own' do
      expect(scope.to_a).not_to include(legacy_image)
    end
  end
end

RSpec.describe LifeCycleEventPolicy, type: :policy do
  describe 'Scope - tenant leakage' do
    let(:org)       { create(:organization, :real) }
    let(:other_org) { create(:organization, :real) }
    let(:actor)     { org_member_actor(org) }

    let(:org_specimen)     { create(:specimen, :private, owned_by: 'owner@example.org', owner_organization_id: org.id) }
    let!(:org_event)       { create(:harvest_event, specimen: org_specimen) }

    let(:other_specimen)   { create(:specimen, :private, owned_by: 'other@example.org', owner_organization_id: other_org.id) }
    let!(:other_event)     { create(:harvest_event, specimen: other_specimen) }

    let(:legacy_specimen)  { create(:specimen, :private, owned_by: 'legacy@example.org', owner_organization_id: nil) }
    let!(:legacy_event)    { create(:harvest_event, specimen: legacy_specimen) }

    let(:scope) { Pundit.policy_scope(actor, LifeCycleEvent) }

    it 'includes events of org-owned specimens' do
      expect(scope.to_a).to include(org_event)
    end

    it "does NOT include events of other org's specimens" do
      expect(scope.to_a).not_to include(other_event)
    end

    it 'does NOT include events of legacy (null org) specimens the user does not email-own' do
      expect(scope.to_a).not_to include(legacy_event)
    end
  end

  describe 'Scope - NULL owner_organization_id behaves purely legacy' do
    let(:org)       { create(:organization, :real) }

    let(:actor) do
      principal    = create(:principal)
      personal_org = Organization.personal_for!(principal)
      User.new(
        'uid' => principal.external_uid,
        'email' => principal.email,
        'trust_levels' => { 'plant' => 2 },
        'organizations' => [{ 'id' => org.id, 'name' => org.name, 'roles' => { 'plant' => 'editor' } }]
      ).tap do |u|
        u.principal = principal
        u.personal_organization = personal_org
      end
    end

    let(:legacy_specimen_own) { create(:specimen, :private, owned_by: actor.email, owner_organization_id: nil) }
    let(:legacy_specimen_other) { create(:specimen, :private, owned_by: 'other@example.org', owner_organization_id: nil) }
    let!(:own_event)   { create(:harvest_event, specimen: legacy_specimen_own) }
    let!(:other_event) { create(:harvest_event, specimen: legacy_specimen_other) }

    let(:scope) { Pundit.policy_scope(actor, LifeCycleEvent) }

    it 'shows events of own-email specimens (legacy path)' do
      expect(scope.to_a).to include(own_event)
    end

    it 'hides events of other-email specimens with NULL org (legacy path)' do
      expect(scope.to_a).not_to include(other_event)
    end
  end
end
