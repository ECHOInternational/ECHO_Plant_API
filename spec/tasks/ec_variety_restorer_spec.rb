# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/ec_variety_restorer')

RSpec.describe EcVarietyRestorer do
  let(:org) { create(:organization, :real) }
  let(:principal) { create(:principal) }
  let(:plant) do
    create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
  end

  def variety(**overrides)
    create(:variety, { plant_id: plant.id, owner_organization_id: org.id,
                       source_organization_id: org.id,
                       deleted_at: Time.current }.merge(overrides))
  end

  def restore(uuids, apply: true)
    described_class.new(principal: principal, apply: apply).restore(uuids)
  end

  it 'clears deleted_at on a soft-deleted variety' do
    v = variety
    result = restore([v.id])

    expect(result.restored).to eq 1
    expect(v.reload.deleted_at).to be_nil
  end

  # Merely clearing deleted_at leaves the trio resolving to :private, which
  # keeps the record out of the public set the cutover guard measures.
  it 'returns it to the public set rather than just un-deleting it' do
    v = variety
    restore([v.id])

    expect(v.reload.access_level).to eq 'public'
    expect(v.publication_state).to eq 'published'
    expect(v.visibility).to eq 'public'
  end

  # This reverses a named person's edit, so the version must say who did it.
  it 'attributes the change to the migration principal', :versioning do
    v = variety
    restore([v.id])

    version = PaperTrail::Version.where(item_type: 'Variety', item_id: v.id).last
    expect(version.whodunnit).to eq principal.id
  end

  it 'leaves a variety that is not deleted alone' do
    v = variety(deleted_at: nil, publication_state: 'draft',
                access_level: 'organization')
    result = restore([v.id])

    expect(result.not_deleted).to eq 1
    expect(result.restored).to eq 0
    expect(v.reload.access_level).to eq 'organization'
  end

  it 'reports a variety that is not in the API and never creates one' do
    expect { restore([SecureRandom.uuid]) }.not_to change(Variety.unscoped, :count)
    expect(restore([SecureRandom.uuid]).missing).to eq 1
  end

  it 'writes nothing on a dry run' do
    v = variety
    result = restore([v.id], apply: false)

    expect(result.restored).to eq 1
    expect(v.reload.deleted_at).to be_present
  end

  it 'reports each outcome separately over a mixed batch' do
    gone = variety
    live = variety(deleted_at: nil)
    result = restore([gone.id, live.id, SecureRandom.uuid])

    expect(result).to have_attributes(restored: 1, not_deleted: 1, missing: 1,
                                      failed: 0)
  end
end
