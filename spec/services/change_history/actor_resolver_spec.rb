# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::ActorResolver, versioning: true do
  subject(:resolver) { described_class.new }

  def version_for(plant)
    PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id).last
  end

  it 'resolves the principal named in metadata.principal_id' do
    principal = create(:principal, display_name: 'Data Steward')
    plant = create(:plant)
    PaperTrail.request(controller_info: { metadata: { origin: 'api', principal_id: principal.id } }) do
      plant.update!(scientific_name: 'Changed')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to eq principal
    expect(resolver.label_for(version)).to eq 'Data Steward'
  end

  it 'resolves a whodunnit that is itself a principal id (sync writes)' do
    principal = create(:principal, :service, display_name: 'Import Service')
    plant = create(:plant)
    PaperTrail.request(whodunnit: principal.id, controller_info: { metadata: { origin: 'sync' } }) do
      plant.update!(scientific_name: 'Synced')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to eq principal
    expect(resolver.label_for(version)).to eq 'Import Service'
  end

  it 'resolves a whodunnit that is a JWT uid' do
    principal = create(:principal, display_name: nil, external_uid: SecureRandom.uuid)
    plant = create(:plant)
    PaperTrail.request(whodunnit: principal.external_uid) do
      plant.update!(scientific_name: 'By uid')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to eq principal
    expect(resolver.label_for(version)).to eq principal.email
  end

  it 'falls back to a label when nothing resolves' do
    plant = create(:plant)
    PaperTrail.request(whodunnit: 'sandbox') do
      plant.update!(scientific_name: 'Anonymous')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to be_nil
    expect(resolver.label_for(version)).to eq described_class::UNKNOWN_LABEL
  end

  it 'labels unattributed sync writes as an automated import' do
    plant = create(:plant)
    PaperTrail.request(controller_info: { metadata: { origin: 'sync' } }) do
      plant.update!(scientific_name: 'Machine')
    end

    version = version_for(plant)
    expect(resolver.label_for(version)).to eq described_class::SYNC_LABEL
  end

  it 'queries once per distinct actor' do
    principal = create(:principal)
    plant = create(:plant)
    PaperTrail.request(controller_info: { metadata: { principal_id: principal.id } }) do
      plant.update!(scientific_name: 'A')
      plant.update!(scientific_name: 'B')
    end

    versions = PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id).to_a
    allow(Principal).to receive(:find_by).and_call_original
    versions.each { |version| resolver.principal_for(version) }

    expect(Principal).to have_received(:find_by).once
  end
end
