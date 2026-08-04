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

  # The case that actually happened: staging had 2,680 owned records and no
  # organizations at all, and the first version of this audit reported PASS,
  # because its join on owner_organization_id could not see a single one of
  # them. A vacuous pass is worse than no check.
  it 'fails loudly on a database that was never backfilled' do
    create(:plant, :private, owned_by: 'someone@example.com')

    expect { run }
      .to raise_error(SystemExit)
      .and output(/NOT READY: 1 records have no owner organization at all/).to_stdout
  end

  it 'passes when every personally-owned record has a resolvable owner' do
    principal = create(:principal) # a real IdP identity: external_uid present
    org = Organization.personal_for!(principal)
    create(:plant, :private, owned_by: principal.email,
                             owner_organization_id: org.id, source_organization_id: org.id)

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
    # Factories build associated records (a specimen brings a plant and a
    # variety) without ownership, and the un-backfilled check runs first and
    # would abort before the per-model counting this example is about. Give
    # those incidental rows the same owner so the subject under test is the
    # counting, not the setup.
    [Plant, Variety, Specimen, Location, Category].each do |model|
      model.where(owner_organization_id: nil)
           .update_all(owner_organization_id: org.id, source_organization_id: org.id)
    end

    expect { run }
      .to raise_error(SystemExit)
      .and output(/"plants" => \d+.*"varieties" => \d+.*"specimens" => \d+.*"locations" => \d+.*"categories" => \d+/m)
      .to_stdout
  end
end
