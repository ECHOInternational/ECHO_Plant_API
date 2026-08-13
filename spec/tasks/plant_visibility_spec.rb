# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EcVisibilityAligner do
  let(:org)   { create(:organization, :real) }
  let(:other) { create(:organization, :real) }

  def plant(visibility:, organization: org)
    create(:plant, owner_organization_id: organization.id,
                   source_organization_id: organization.id,
                   visibility: visibility)
  end

  def align(statuses, apply: true)
    described_class.new(organization: org, statuses: statuses, apply: apply).align
  end

  it 'hides a plant ECHOcommunity has as draft' do
    p = plant(visibility: :public)
    result = align({ p.id => 'draft' })

    expect(result.changed).to eq 1
    expect(p.reload.visibility).to eq 'draft'
  end

  it 'hides a plant ECHOcommunity has deleted' do
    p = plant(visibility: :public)
    align({ p.id => 'deleted' })

    expect(p.reload.visibility).to eq 'deleted'
  end

  it 'publishes a plant ECHOcommunity has published' do
    p = plant(visibility: :draft)
    align({ p.id => 'published' })

    expect(p.reload.visibility).to eq 'public'
  end

  it 'counts an already-correct plant as unchanged and writes nothing' do
    p = plant(visibility: :public)
    result = align({ p.id => 'published' })

    expect(result.changed).to eq 0
    expect(result.unchanged).to eq 1
  end

  # Absence from the status file means "ECHOcommunity has never heard of this",
  # which is true of the 107 contributed plants and the 2026-08-07 Acacia split.
  # Silence must not be read as a deletion.
  it 'leaves a plant absent from the status file untouched' do
    p = plant(visibility: :public)
    result = align({})

    expect(result.absent).to eq 1
    expect(p.reload.visibility).to eq 'public'
  end

  it 'ignores plants owned by another organization' do
    p = plant(visibility: :public, organization: other)
    align({ p.id => 'draft' })

    expect(p.reload.visibility).to eq 'public'
  end

  it 'writes nothing when not applying' do
    p = plant(visibility: :public)
    result = align({ p.id => 'draft' }, apply: false)

    expect(result.changed).to eq 1
    expect(p.reload.visibility).to eq 'public'
  end
end
