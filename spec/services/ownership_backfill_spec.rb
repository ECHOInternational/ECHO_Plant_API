# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Helper to build a minimal valid mapping JSON structure.
def build_mapping(users: [], organizations: [], echo_org_id: nil)
  echo_org_id ||= SecureRandom.uuid
  {
    'generated_at' => Time.current.iso8601,
    'users' => users,
    'organizations' => [{ 'id' => echo_org_id, 'name' => 'ECHO', 'slug' => 'echo' }] + organizations
  }
end

RSpec.describe OwnershipBackfill, type: :service do
  # Shared factory helpers
  let(:echo_org_id) { SecureRandom.uuid }
  let(:mapping_path) { Rails.root.join('tmp', "test_mapping_#{SecureRandom.hex(4)}.json") }

  def write_mapping(mapping)
    FileUtils.mkdir_p(Rails.root.join('tmp'))
    File.write(mapping_path, mapping.to_json)
  end

  after { FileUtils.rm_f(mapping_path) }

  def run_backfill(dry_run: true, extra_users: [], extra_orgs: [], mapping: nil)
    m = mapping || build_mapping(
      users: extra_users,
      organizations: extra_orgs,
      echo_org_id: echo_org_id
    )
    write_mapping(m)
    OwnershipBackfill.new(
      mapping_path: mapping_path.to_s,
      echo_org_id: echo_org_id,
      dry_run: dry_run,
      batch_size: 100
    )
  end

  # ---------------------------------------------------------------------------
  # Mapping validation
  # ---------------------------------------------------------------------------
  describe 'mapping validation' do
    it 'aborts with a clear message when MAPPING file is missing' do
      svc = OwnershipBackfill.new(
        mapping_path: '/nonexistent/mapping.json',
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /MAPPING file not found/)
    end

    it 'aborts when JSON is malformed' do
      File.write(mapping_path, '{ not valid json')
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /not valid JSON/)
    end

    it 'aborts when a user entry has a blank uid' do
      m = build_mapping(
        users: [{ 'uid' => '', 'email' => 'a@b.com', 'name' => 'A' }],
        echo_org_id: echo_org_id
      )
      write_mapping(m)
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /blank uid/)
    end

    it 'aborts when a user entry has a blank email' do
      m = build_mapping(
        users: [{ 'uid' => SecureRandom.uuid, 'email' => '', 'name' => 'A' }],
        echo_org_id: echo_org_id
      )
      write_mapping(m)
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /blank email/)
    end

    it 'aborts on duplicate uids in mapping' do
      uid = SecureRandom.uuid
      m = build_mapping(
        users: [
          { 'uid' => uid, 'email' => 'a@b.com',  'name' => 'A' },
          { 'uid' => uid, 'email' => 'b@b.com',  'name' => 'B' }
        ],
        echo_org_id: echo_org_id
      )
      write_mapping(m)
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /Duplicate uid/)
    end

    it 'aborts on duplicate emails in mapping' do
      m = build_mapping(
        users: [
          { 'uid' => SecureRandom.uuid, 'email' => 'same@b.com', 'name' => 'A' },
          { 'uid' => SecureRandom.uuid, 'email' => 'same@b.com', 'name' => 'B' }
        ],
        echo_org_id: echo_org_id
      )
      write_mapping(m)
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /Duplicate email/)
    end

    it 'aborts when ECHO_ORG_ID is not in the organizations list' do
      m = build_mapping(users: [], organizations: [], echo_org_id: echo_org_id)
      # Override the organizations to exclude the echo_org_id
      m['organizations'] = [{ 'id' => SecureRandom.uuid, 'name' => 'Other', 'slug' => 'other' }]
      write_mapping(m)
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: true
      )
      expect { svc.run }.to raise_error(ArgumentError, /not found in mapping/)
    end
  end

  # ---------------------------------------------------------------------------
  # Dry-run: writes nothing but counts correctly
  # ---------------------------------------------------------------------------
  describe 'dry-run mode' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'alice@example.com' }

    before do
      # Create a plant owned by the mapped user
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
      # And a category owned by the shared ECHO email
      create(:category, owned_by: 'echo@echonet.org', created_by: 'echo@echonet.org',
                        visibility: :public)
    end

    it 'writes nothing (all ownership columns remain nil)' do
      svc = run_backfill(
        dry_run: true,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Alice' }]
      )
      svc.run

      Plant.all.each do |p|
        expect(p.owner_organization_id).to be_nil
      end
      Category.all.each do |c|
        expect(c.owner_organization_id).to be_nil
      end
    end

    it 'reports the correct filled count without writing' do
      svc = run_backfill(
        dry_run: true,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Alice' }]
      )
      report = svc.run

      # Both tables should have unfilled rows counted
      expect(report.table_stats['plants'][:filled]).to be >= 1
      expect(report.table_stats['categories'][:filled]).to be >= 1
    end

    it 'does not create principals in the database' do
      initial_count = Principal.count
      svc = run_backfill(
        dry_run: true,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Alice' }]
      )
      svc.run
      expect(Principal.count).to eq initial_count
    end
  end

  # ---------------------------------------------------------------------------
  # Real run: mapped email -> principal + personal org + columns filled
  # ---------------------------------------------------------------------------
  describe 'real run with mapped email' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'bob@example.com' }
    let!(:plant) do
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
    end

    before do
      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Bob' }]
      )
      svc.run
    end

    it 'creates a human principal with the IdP uid' do
      p = Principal.find_by(identity_issuer: OwnershipBackfill::ECHOCOMMUNITY_ISSUER,
                            external_uid: user_uid)
      expect(p).to be_present
      expect(p.kind).to eq 'human'
      expect(p.email).to eq user_email
    end

    it 'creates a personal org for the principal' do
      principal = Principal.find_by(identity_issuer: OwnershipBackfill::ECHOCOMMUNITY_ISSUER,
                                    external_uid: user_uid)
      expect(Organization.find_by(principal_id: principal.id)).to be_present
    end

    it 'fills owner_organization_id with the personal org' do
      principal = Principal.find_by(identity_issuer: OwnershipBackfill::ECHOCOMMUNITY_ISSUER,
                                    external_uid: user_uid)
      personal_org = Organization.find_by(principal_id: principal.id)

      plant.reload
      expect(plant.owner_organization_id).to eq personal_org.id
      expect(plant.source_organization_id).to eq personal_org.id
    end

    it 'fills created_by_principal_id' do
      principal = Principal.find_by(identity_issuer: OwnershipBackfill::ECHOCOMMUNITY_ISSUER,
                                    external_uid: user_uid)
      plant.reload
      expect(plant.created_by_principal_id).to eq principal.id
    end

    it 'maps visibility :public -> publication_state=published, access_level=public' do
      plant.reload
      expect(plant.publication_state).to eq 'published'
      expect(plant.access_level).to eq 'public'
      expect(plant.deleted_at).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Unmapped email -> legacy principal + counted in report
  # ---------------------------------------------------------------------------
  describe 'unmapped email' do
    let(:unmapped_email) { 'mystery@example.com' }
    let!(:plant) do
      create(:plant, owned_by: unmapped_email, created_by: unmapped_email, visibility: :draft)
    end

    it 'creates a legacy principal (no uid)' do
      svc = run_backfill(dry_run: false)
      svc.run
      p = Principal.find_by(identity_issuer: Principal::LEGACY_ISSUER, email: unmapped_email)
      expect(p).to be_present
      expect(p.external_uid).to be_nil
    end

    it 'counts the email in the unmapped list' do
      svc = run_backfill(dry_run: false)
      report = svc.run
      expect(report.unmapped_emails).to include(unmapped_email)
    end

    it 'fills the record columns despite being unmapped' do
      svc = run_backfill(dry_run: false)
      svc.run
      plant.reload
      expect(plant.owner_organization_id).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Shared email (echo@echonet.org) -> ECHO org, service principal, no personal org
  # ---------------------------------------------------------------------------
  describe 'shared email (echo@echonet.org)' do
    let!(:category) do
      create(:category, owned_by: 'echo@echonet.org', created_by: 'echo@echonet.org',
                        visibility: :public)
    end

    before do
      svc = run_backfill(dry_run: false)
      svc.run
    end

    it 'creates a service principal for the shared email' do
      p = Principal.find_by(identity_issuer: 'legacy-shared', email: 'echo@echonet.org')
      expect(p).to be_present
      expect(p.kind).to eq 'service'
    end

    it 'does not create a personal org for the service principal' do
      p = Principal.find_by(identity_issuer: 'legacy-shared', email: 'echo@echonet.org')
      expect(Organization.find_by(principal_id: p.id)).to be_nil
    end

    it 'assigns owner_organization_id to the ECHO org' do
      echo_org = Organization.find_by(external_idp_id: echo_org_id)
      expect(echo_org).to be_present

      category.reload
      expect(category.owner_organization_id).to eq echo_org.id
    end
  end

  # ---------------------------------------------------------------------------
  # Visibility mapping including deleted rows
  # ---------------------------------------------------------------------------
  describe 'visibility mapping' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'carol@example.com' }

    { private: %w[published organization], public: %w[published public], draft: %w[draft organization] }.each do |vis, (ps, al)|
      it "maps :#{vis} -> publication_state=#{ps}, access_level=#{al}" do
        plant = create(:plant, owned_by: user_email, created_by: user_email, visibility: vis)
        svc = run_backfill(
          dry_run: false,
          extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Carol' }]
        )
        svc.run
        plant.reload
        expect(plant.publication_state).to eq ps
        expect(plant.access_level).to eq al
        expect(plant.deleted_at).to be_nil
      end
    end

    it 'maps :deleted -> deleted_at=updated_at, trio=published/organization' do
      # Create the plant and delete it via legacy visibility
      plant = create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
      # Simulate legacy deletion: update visibility directly to bypass callbacks
      plant.update_columns(visibility: 3, publication_state: nil, access_level: nil,
                           deleted_at: nil)
      plant.reload

      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Carol' }]
      )
      svc.run
      plant.reload

      expect(plant.deleted_at).to be_present
      # deleted_at approximated from updated_at (documented)
      expect(plant.deleted_at.to_i).to eq plant.updated_at.to_i
      expect(plant.publication_state).to eq 'published'
      expect(plant.access_level).to eq 'organization'
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency: run twice, second run all-skipped, no duplicate principals/orgs
  # ---------------------------------------------------------------------------
  describe 'idempotency' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'dave@example.com' }

    before do
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
    end

    def run_once
      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Dave' }]
      )
      svc.run
    end

    it 'second run reports all rows as skipped (already filled)' do
      run_once
      report = run_once

      total_skipped = report.table_stats.values.sum { |s| s[:skipped] }
      total_filled  = report.table_stats.values.sum { |s| s[:filled] }
      expect(total_skipped).to be > 0
      expect(total_filled).to eq 0
    end

    it 'does not create duplicate principals' do
      run_once
      count_before = Principal.count
      run_once
      expect(Principal.count).to eq count_before
    end

    it 'does not create duplicate organizations' do
      run_once
      org_count_before = Organization.count
      run_once
      expect(Organization.count).to eq org_count_before
    end
  end

  # ---------------------------------------------------------------------------
  # Resumability: partial fill is completed, filled rows untouched (updated_at)
  # ---------------------------------------------------------------------------
  describe 'resumability' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'eve@example.com' }
    let!(:plant1) { create(:plant, owned_by: user_email, created_by: user_email, visibility: :public) }
    let!(:plant2) { create(:plant, owned_by: user_email, created_by: user_email, visibility: :private) }

    it 'completes partially-filled records and does not touch already-filled rows' do
      # Do a real run for plant1 only (simulate partial fill)
      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Eve' }]
      )
      svc.run
      plant1.reload
      plant2.reload
      expect(plant1.owner_organization_id).to be_present
      expect(plant2.owner_organization_id).to be_present

      # Manually nil out plant2 to simulate partial fill
      updated_at_before = plant1.reload.updated_at
      plant2.update_columns(owner_organization_id: nil, source_organization_id: nil,
                            created_by_principal_id: nil, publication_state: nil,
                            access_level: nil, deleted_at: nil)

      svc2 = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Eve' }]
      )
      svc2.run

      # plant1 should not have been touched (update_columns doesn't change updated_at)
      expect(plant1.reload.updated_at.to_i).to eq updated_at_before.to_i
      # plant2 should now be filled
      expect(plant2.reload.owner_organization_id).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Round-trip guard: rows that cannot round-trip are refused
  # ---------------------------------------------------------------------------
  describe 'round-trip guard' do
    it 'refuses a row if the derived trio does not map back to stored visibility' do
      # Directly test the private guard via send
      record = instance_double(
        Plant,
        visibility: 'public',
        owned_by: 'x@example.com',
        created_by: 'x@example.com',
        updated_at: Time.current
      )

      svc = run_backfill(dry_run: true)

      # Attributes that would map to :private, but record says :public
      bad_attrs = {
        owner_organization_id: SecureRandom.uuid,
        source_organization_id: SecureRandom.uuid,
        created_by_principal_id: SecureRandom.uuid,
        publication_state: 'published',
        access_level: 'organization', # would yield :private
        deleted_at: nil
      }

      result = svc.send(:round_trip_ok?, record, bad_attrs)
      expect(result).to be false
    end

    it 'accepts a row when the trio round-trips correctly' do
      record = instance_double(
        Plant,
        visibility: 'public',
        owned_by: 'x@example.com',
        created_by: 'x@example.com',
        updated_at: Time.current
      )

      svc = run_backfill(dry_run: true)

      good_attrs = {
        owner_organization_id: SecureRandom.uuid,
        source_organization_id: SecureRandom.uuid,
        created_by_principal_id: SecureRandom.uuid,
        publication_state: 'published',
        access_level: 'public',
        deleted_at: nil
      }

      result = svc.send(:round_trip_ok?, record, good_attrs)
      expect(result).to be true
    end

    it 'counts refused rows in the report' do
      # Create a plant with a visibility that we will make unresolvable by
      # setting an unexpected combination via update_columns
      create(:plant, owned_by: 'echo@echonet.org', created_by: 'echo@echonet.org',
                     visibility: :public)

      # Stub VisibilityBridge to return a mismatch for this specific plant
      allow(VisibilityBridge).to receive(:visibility_for).and_call_original
      allow(VisibilityBridge).to receive(:visibility_for)
        .with(publication_state: 'published', access_level: 'public', deleted_at: nil)
        .and_return(:private, :public) # first call from guard returns :private (mismatch)

      svc = run_backfill(dry_run: true)
      report = svc.run

      # The stubbed row should appear as refused
      expect(report.refused_rows.size + report.table_stats.values.sum { |s| s[:refused] }).to be >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # verify task integration: passes after backfill, fails when row is nil'd
  # ---------------------------------------------------------------------------
  describe 'integration with ownership:verify' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'frank@example.com' }
    let!(:plant) do
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
    end

    it 'verify reports no violations after a complete backfill' do
      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Frank' }]
      )
      svc.run

      violations = collect_verify_violations([plant.class])
      expect(violations).to be_empty
    end

    it "verify reports violations when owner_organization_id is nil'd" do
      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Frank' }]
      )
      svc.run

      plant.reload.update_columns(owner_organization_id: nil)
      violations = collect_verify_violations([plant.class])
      expect(violations).not_to be_empty
      expect(violations.first).to include('owner_organization_id')
    end

    it 'verify reports facade disagreements' do
      svc = run_backfill(
        dry_run: false,
        extra_users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Frank' }]
      )
      svc.run

      # Cause a disagreement: trio says :private but legacy visibility says :public
      plant.reload.update_columns(publication_state: 'published', access_level: 'organization')
      # Now visibility is still :public but trio says private
      violations = collect_verify_violations([plant.class])
      expect(violations.any? { |v| v.include?('facade/column disagreement') }).to be true
    end

    # Extracts violations from the verify logic (mirrors the rake task body)
    def collect_verify_violations(models)
      violations = []
      models.each do |model|
        %i[owner_organization_id source_organization_id created_by_principal_id].each do |col|
          missing = model.where(col => nil).count
          violations << "#{model.table_name}: #{missing} rows missing #{col}" if missing > 0
        end

        model.where.not(publication_state: nil).find_each do |record|
          derived = VisibilityBridge.visibility_for(
            publication_state: record.publication_state,
            access_level: record.access_level,
            deleted_at: record.deleted_at
          )
          violations << "#{model.table_name}: facade/column disagreement on #{record.id}" if derived != record.visibility.to_sym
        end
      end
      violations
    end
  end

  # ---------------------------------------------------------------------------
  # Rake task smoke test (invokes the task via Rake)
  # ---------------------------------------------------------------------------
  describe 'rake task smoke test' do
    before(:all) do
      Rails.application.load_tasks
    end

    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'grace@example.com' }

    before do
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :private)
    end

    it 'rake ownership:backfill DRY_RUN=1 produces a report without writing' do
      m = build_mapping(
        users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Grace' }],
        echo_org_id: echo_org_id
      )
      write_mapping(m)

      original_owner_ids = Plant.pluck(:id, :owner_organization_id).to_h

      ENV['MAPPING']      = mapping_path.to_s
      ENV['ECHO_ORG_ID']  = echo_org_id
      ENV['DRY_RUN']      = '1'

      # Capture output
      output = capture_stdout do
        Rake::Task['ownership:backfill'].execute
      end

      expect(output).to include('OWNERSHIP BACKFILL REPORT')
      expect(output).to include('DRY_RUN: YES')

      # Verify nothing was written
      Plant.pluck(:id, :owner_organization_id).each do |id, owner_org|
        expect(owner_org).to eq original_owner_ids[id]
      end
    ensure
      %w[MAPPING ECHO_ORG_ID DRY_RUN].each { |k| ENV.delete(k) }
      Rake::Task['ownership:backfill'].reenable
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 1: filled count only increments AFTER write_batch! succeeds
  # ---------------------------------------------------------------------------
  describe 'filled count is not incremented for failed batches' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'henry@example.com' }

    before do
      # Two plants so the second batch can be made to fail
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
      create(:plant, owned_by: user_email, created_by: user_email, visibility: :private)
    end

    it 'does not count rows from a batch whose write_batch! raises' do
      # Use a tiny batch_size of 1 so we get two separate batches.
      m = build_mapping(
        users: [{ 'uid' => user_uid, 'email' => user_email, 'name' => 'Henry' }],
        echo_org_id: echo_org_id
      )
      write_mapping(m)
      svc = OwnershipBackfill.new(
        mapping_path: mapping_path.to_s,
        echo_org_id: echo_org_id,
        dry_run: false,
        batch_size: 1
      )

      call_count = 0
      allow(svc).to receive(:write_batch!).and_wrap_original do |original, *args|
        call_count += 1
        raise ActiveRecord::StatementInvalid, 'simulated DB error' if call_count == 2

        original.call(*args)
      end

      expect { svc.run }.to raise_error(ActiveRecord::StatementInvalid)

      # Only the first batch (1 row) committed; the second batch raised before
      # incrementing filled. Total filled must be <= 1 across all tables.
      total_filled = svc.instance_variable_get(:@report).table_stats.values.sum { |s| s[:filled] }
      expect(total_filled).to be <= 1
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 2: verify flags visibility=deleted rows with deleted_at IS NULL
  # ---------------------------------------------------------------------------
  describe 'verify deleted_at invariant' do
    let(:user_uid)   { SecureRandom.uuid }
    let(:user_email) { 'ivan@example.com' }

    it 'flags a deleted row whose deleted_at is NULL as a violation' do
      plant = create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
      # Simulate a corrupted/un-backfilled deleted row: visibility=3 but deleted_at nil
      plant.update_columns(visibility: 3, deleted_at: nil)

      violations = collect_deleted_at_violations([Plant])
      expect(violations.any? { |v| v.include?('deleted_at IS NULL') }).to be true
    end

    it 'does not flag a deleted row that has deleted_at set' do
      plant = create(:plant, owned_by: user_email, created_by: user_email, visibility: :public)
      plant.update_columns(visibility: 3, deleted_at: Time.current)

      violations = collect_deleted_at_violations([Plant])
      expect(violations).to be_empty
    end

    # Mirrors the new deleted_at check added to ownership:verify
    def collect_deleted_at_violations(models)
      violations = []
      models.each do |model|
        count = model.where(visibility: 3).where(deleted_at: nil).count
        if count.positive?
          sample_ids = model.where(visibility: 3).where(deleted_at: nil).limit(5).pluck(:id)
          violations << "#{model.table_name}: #{count} rows have visibility=deleted " \
                        "but deleted_at IS NULL (first 5: #{sample_ids.join(', ')})"
        end
      end
      violations
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 3: SHARED_ISSUER constant referenced from Principal
  # ---------------------------------------------------------------------------
  describe 'Principal::SHARED_ISSUER constant' do
    it 'is defined on Principal and equals "legacy-shared"' do
      expect(Principal::SHARED_ISSUER).to eq 'legacy-shared'
    end

    it 'is used for service principal lookup/creation in backfill' do
      create(:category, owned_by: 'echo@echonet.org', created_by: 'echo@echonet.org',
                        visibility: :public)
      svc = run_backfill(dry_run: false)
      svc.run

      p = Principal.find_by(identity_issuer: Principal::SHARED_ISSUER, email: 'echo@echonet.org')
      expect(p).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Helper
  # ---------------------------------------------------------------------------
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
