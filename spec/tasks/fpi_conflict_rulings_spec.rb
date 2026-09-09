# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/fpi_conflict_rulings')

RSpec.describe FpiConflictRulings do
  let(:org) { create(:organization, :real) }
  let(:data_source) { FpiDataSource.find_or_create!(organization: org) }
  let(:other_source) { create(:data_source, organization: org) }
  let(:reviewer) { create(:principal) }
  let(:base) { { 'scientific_name' => 'Upstream', 'family_names' => 'Moringaceae' } }

  def plant(src_id, source: data_source)
    create(:plant, data_source_id: source.id, source_record_id: src_id, source_snapshot: base, scientific_name: 'Curator',
                   family_names: 'Moringaceae', owner_organization_id: org.id, source_organization_id: org.id)
  end

  def conflict(plant, source: data_source, status: 'open', type: 'content')
    create(:sync_conflict, syncable: plant, data_source: source, conflict_type: type, status: status,
                           base_payload: base, local_payload: base.merge('scientific_name' => 'Curator'),
                           incoming_payload: type == 'content' ? base.merge('scientific_name' => 'Newer upstream') : {})
  end

  def rulings_for(pairs)
    pairs.map { |c, r| { 'conflict_id' => c.is_a?(String) ? c : c.id, 'resolution' => r } }
  end

  it 'counts what it would do on a dry run and changes nothing' do
    keep = conflict(plant('p1'))
    accept = conflict(plant('p2'))
    result = described_class.new(data_source: data_source, principal: reviewer, decision: 'D-060').apply(rulings_for([[keep, 'KEEP_LOCAL'], [accept, 'ACCEPT_INCOMING']]))
    expect(result.applied).to eq(2)
    expect([keep.reload.status, accept.reload.status]).to eq(%w[open open])
  end

  it 'applies each ruling through the shared resolution and stamps the reviewer' do
    keep = conflict(plant('p1'))
    accept = conflict(plant('p2'))
    gone = conflict(plant('p3'), type: 'source_deletion')
    result = described_class.new(data_source: data_source, principal: reviewer, decision: 'D-060', apply: true)
                            .apply(rulings_for([[keep, 'KEEP_LOCAL'], [accept, 'ACCEPT_INCOMING'], [gone, 'ACCEPT_INCOMING']]))
    expect(result.applied).to eq(3)
    expect(result.failed).to eq(0)
    expect(keep.reload).to have_attributes(status: 'resolved', resolution: 'keep_local', resolved_by_principal_id: reviewer.id)
    expect(keep.syncable.reload.scientific_name).to eq('Curator')
    expect(keep.syncable.source_snapshot['scientific_name']).to eq('Newer upstream')
    expect(accept.reload.resolution).to eq('accept_incoming')
    expect(accept.syncable.reload.scientific_name).to eq('Newer upstream')
    expect(gone.syncable.reload.visibility).to eq('deleted')
  end

  it 'refuses rulings for closed, foreign, unknown or oddly resolved conflicts and counts them' do
    closed = conflict(plant('p1'), status: 'resolved')
    foreign = conflict(plant('p2', source: other_source), source: other_source)
    odd = conflict(plant('p3'))
    result = described_class.new(data_source: data_source, principal: reviewer, decision: 'D-060', apply: true)
                            .apply(rulings_for([[closed, 'KEEP_LOCAL'], [foreign, 'KEEP_LOCAL'], [SecureRandom.uuid, 'KEEP_LOCAL'], [odd, 'DELETE_EVERYTHING']]))
    expect(result.to_h.slice(:applied, :not_open, :missing, :refused, :failed)).to eq(applied: 0, not_open: 1, missing: 2, refused: 1, failed: 0)
    expect(result.errors.first).to match(/unknown resolution "DELETE_EVERYTHING"/)
    expect(odd.reload.status).to eq('open')
  end
end
