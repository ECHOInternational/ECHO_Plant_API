# frozen_string_literal: true

require 'rails_helper'

# Runbook stage S6: ORG_AUTHZ_CUTOVER=log_only emits authz.legacy_divergence
# for accesses granted ONLY by a legacy branch (would be denied once legacy
# authorization is removed). Zero such events is the S7 cleanup gate.
RSpec.describe 'authz.legacy_divergence logging', type: :model do
  # A trust-2 owner-by-email with no organization membership: update? is granted
  # only by the legacy email branch, so it diverges from the org model.
  let(:owner) { build(:user, :readwrite, email: 'owner@example.org') }
  let(:record) do
    create(:plant, :private, owned_by: 'owner@example.org',
                             owner_organization_id: nil)
  end
  let(:policy) { PlantPolicy.new(owner, record) }

  around do |example|
    original = ENV.fetch('ORG_AUTHZ_CUTOVER', nil)
    example.run
    if original.nil?
      ENV.delete('ORG_AUTHZ_CUTOVER')
    else
      ENV['ORG_AUTHZ_CUTOVER'] = original
    end
  end

  it 'does not log when the flag is unset' do
    ENV.delete('ORG_AUTHZ_CUTOVER')
    expect(Rails.logger).not_to receive(:info)
    expect(policy.update?).to be true
  end

  it 'logs a legacy-only grant when the flag is log_only' do
    ENV['ORG_AUTHZ_CUTOVER'] = 'log_only'
    expect(Rails.logger).to receive(:info) do |payload|
      parsed = JSON.parse(payload)
      expect(parsed['event']).to eq('authz.legacy_divergence')
      expect(parsed['action']).to eq('update')
      expect(parsed['decision']).to eq('granted_by_legacy_only')
    end
    expect(policy.update?).to be true
  end

  it 'does not log when the organization branch also grants access' do
    ENV['ORG_AUTHZ_CUTOVER'] = 'log_only'
    org = create(:organization, :real)
    org_record = create(:plant, :private, owned_by: 'someone@else.org',
                                          owner_organization_id: org.id)
    editor = build(:user, :readwrite, email: 'editor@example.org',
                                      organizations: [{ 'id' => org.id, 'name' => 'ECHO',
                                                        'roles' => { 'plant' => 'editor' } }])
    expect(Rails.logger).not_to receive(:info)
    expect(PlantPolicy.new(editor, org_record).update?).to be true
  end
end
