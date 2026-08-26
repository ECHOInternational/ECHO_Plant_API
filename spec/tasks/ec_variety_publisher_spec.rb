# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_variety_publisher')

RSpec.describe EcVarietyPublisher do
  let(:org) { create(:organization, :real) }
  let(:other_org) { create(:organization, :real) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  def variety(**overrides)
    create(:variety, { plant_id: plant.id, owner_organization_id: org.id,
                       source_organization_id: org.id,
                       publication_state: 'draft',
                       access_level: 'organization' }.merge(overrides))
  end

  def publish(uuids, apply: true)
    described_class.new(organization: org, apply: apply).publish(uuids)
  end

  it 'publishes an organization-only variety' do
    v = variety
    result = publish([v.id])

    expect(result.published).to eq 1
    expect(v.reload.access_level).to eq 'public'
    expect(v.publication_state).to eq 'published'
  end

  # The trio is authoritative on save; the legacy integer must follow it rather
  # than being left at its old draft value.
  it 'leaves the legacy visibility column consistent with the trio' do
    v = variety
    publish([v.id])

    expect(v.reload.visibility).to eq 'public'
  end

  # Earleaf Acacia. Deleted in plant-admin while ECHOcommunity still publishes
  # it; which side is right is a human decision, so this must not answer it.
  it 'never resurrects a soft-deleted variety' do
    v = variety(deleted_at: Time.current)
    result = publish([v.id])

    expect(result.deleted).to eq 1
    expect(result.published).to eq 0
    expect(v.reload.deleted_at).to be_present
    expect(v.access_level).to eq 'organization'
  end

  # D-006 scopes the public view by owning organization, so publishing another
  # organization's record would put it on echocommunity.org.
  it 'leaves a variety owned by another organization alone' do
    v = variety(owner_organization_id: other_org.id)
    result = publish([v.id])

    expect(result.not_echo_owned).to eq 1
    expect(v.reload.access_level).to eq 'organization'
  end

  it 'reports a variety that is not in the API and never creates one' do
    expect { publish([SecureRandom.uuid]) }.not_to change(Variety.unscoped, :count)
    expect(publish([SecureRandom.uuid]).missing).to eq 1
  end

  it 'is idempotent: an already-public variety is counted, not rewritten' do
    v = variety
    publish([v.id])
    result = publish([v.id])

    expect(result.already_public).to eq 1
    expect(result.published).to eq 0
  end

  it 'writes nothing on a dry run' do
    v = variety
    result = publish([v.id], apply: false)

    expect(result.published).to eq 1
    expect(v.reload.access_level).to eq 'organization'
  end

  # Sixteen of the 26 sit under a draft parent, which is what ECHOcommunity has
  # too - a variety's status is independent of its parent's.
  it 'publishes a variety whose parent plant is still draft' do
    draft_parent = create(:plant, owner_organization_id: org.id,
                                  source_organization_id: org.id,
                                  publication_state: 'draft',
                                  access_level: 'organization')
    v = variety(plant_id: draft_parent.id)
    result = publish([v.id])

    expect(result.published).to eq 1
    expect(v.reload.access_level).to eq 'public'
  end

  it 'reports each guard separately over a mixed batch' do
    ok = variety
    gone = variety(deleted_at: Time.current)
    theirs = variety(owner_organization_id: other_org.id)
    live = variety(publication_state: 'published', access_level: 'public')

    result = publish([ok.id, gone.id, theirs.id, live.id, SecureRandom.uuid])

    expect(result).to have_attributes(published: 1, deleted: 1, not_echo_owned: 1,
                                      already_public: 1, missing: 1, failed: 0)
  end
end
