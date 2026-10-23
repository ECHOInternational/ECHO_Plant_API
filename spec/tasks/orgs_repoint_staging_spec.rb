# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# The operator surface of StagingOrgRepoint (spec/lib/staging_org_repoint_spec.rb
# covers the behavior): ENV parsing, the guards, and the lock.
RSpec.describe 'orgs:repoint_staging', type: :task do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:placeholder_id) { 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0001' }
  let(:target_id)      { '149f6971-b63a-45e7-be7f-e67fc7d7b3d6' }
  let!(:plant) do
    Organization.mirror_real!(external_id: placeholder_id, name: 'ECHO (staging rehearsal)')
    create(:plant, owner_organization_id: placeholder_id, source_organization_id: placeholder_id)
  end

  before do
    allow(ActiveRecord::Base.connection).to receive(:current_database).and_return('Plant_API_staging')
  end

  # Only the ECHO pair: the FPI placeholder is not in this database.
  def invoke(env = {})
    keys = { 'FROM' => placeholder_id, 'TO' => target_id }.merge(env)
    keys.each { |k, v| ENV[k] = v }
    output = StringIO.new
    original = $stdout
    $stdout = output
    Rake::Task['orgs:repoint_staging'].reenable
    Rake::Task['orgs:repoint_staging'].invoke
    output.string
  ensure
    $stdout = original
    keys.each_key { |k| ENV.delete(k) }
  end

  it 'is a dry run by default' do
    expect(invoke).to include('DRY RUN')
    expect(plant.reload.owner_organization_id).to eq(placeholder_id)
  end

  it 'refuses APPLY=true without CONFIRM' do
    expect { invoke('APPLY' => 'true') }.to raise_error(SystemExit)
    expect(plant.reload.owner_organization_id).to eq(placeholder_id)
  end

  it 'applies with APPLY=true and the confirmation value, and REVERSE=true undoes it' do
    invoke('APPLY' => 'true', 'CONFIRM' => 'REPOINT-STAGING-ORGS')
    expect(plant.reload.owner_organization_id).to eq(target_id)

    invoke('APPLY' => 'true', 'CONFIRM' => 'REPOINT-STAGING-ORGS', 'REVERSE' => 'true')
    expect(plant.reload.owner_organization_id).to eq(placeholder_id)
  end

  it 'refuses to run in production' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
    expect { invoke('APPLY' => 'true', 'CONFIRM' => 'REPOINT-STAGING-ORGS') }.to raise_error(SystemExit)
    expect(plant.reload.owner_organization_id).to eq(placeholder_id)
  end

  it 'refuses to apply while another ops write task holds the advisory lock' do
    holder = OpsAdvisoryLock.acquire!('test holder')
    expect { invoke('APPLY' => 'true', 'CONFIRM' => 'REPOINT-STAGING-ORGS') }.to raise_error(SystemExit)
    expect(plant.reload.owner_organization_id).to eq(placeholder_id)
  ensure
    holder&.release
  end
end
