# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# The S7 pre-flight audit is only worth running if it can actually fail, so
# these specs build the unreachable case on purpose and assert it is caught.
RSpec.describe 'ownership:preflight', type: :task do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before { Rake::Task['ownership:preflight'].reenable }

  def run
    Rake::Task['ownership:preflight'].invoke
  end

  # A principal the backfill created from an email alone: no external_uid, so no
  # JWT can ever resolve to it. Records in its personal organization are
  # unreachable once the email rule stops granting access.
  def unreachable_owner
    principal = Principal.legacy_for_email('never-logged-in@example.com')
    Organization.personal_for!(principal)
  end

  it 'passes when every personally-owned record has a resolvable owner' do
    user = build(:user, :readwrite)
    create(:plant, :private, owned_by: user.email)

    expect { run }.to output(/PASS: every personally-owned record is reachable/).to_stdout
  end

  it 'fails and names the owner when a record is owned by an unresolvable principal' do
    org = unreachable_owner
    create(:plant, :private, owned_by: 'never-logged-in@example.com',
                             owner_organization_id: org.id, source_organization_id: org.id)

    expect { run }
      .to raise_error(SystemExit)
      .and output(/never-logged-in@example\.com: 1 records/).to_stdout
  end

  it 'does not flag records owned by a real organization' do
    org = create(:organization, :real)
    create(:plant, :private, owner_organization_id: org.id, source_organization_id: org.id)

    expect { run }.to output(/owned by a REAL organization.*: 1/m).to_stdout
  end

  it 'counts across every owned model, not just plants' do
    org = unreachable_owner
    %i[plant variety specimen location category].each do |kind|
      create(kind, owner_organization_id: org.id, source_organization_id: org.id,
                   owned_by: 'never-logged-in@example.com')
    end

    expect { run }
      .to raise_error(SystemExit)
      .and output(/never-logged-in@example\.com: 5 records/).to_stdout
  end
end
