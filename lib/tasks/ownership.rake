# frozen_string_literal: true

# Ownership backfill, verify, and report rake tasks for the Phase B
# ownership-redesign rollout (Stage S3).
#
# Usage:
#   rake ownership:backfill MAPPING=<path> ECHO_ORG_ID=<uuid>
#   rake ownership:backfill MAPPING=<path> ECHO_ORG_ID=<uuid> DRY_RUN=0
#   rake ownership:backfill MAPPING=<path> ECHO_ORG_ID=<uuid> DRY_RUN=0 BATCH_SIZE=200
#   rake ownership:verify
#   rake ownership:report

namespace :ownership do
  # ---------------------------------------------------------------------------
  # ownership:backfill
  # ---------------------------------------------------------------------------
  desc <<~DESC
    Backfill ownership/publication columns for the five independently-owned tables
    (plants, varieties, specimens, locations, categories). Idempotent, resumable,
    and defaults to DRY_RUN=1 -- no writes unless DRY_RUN=0.

    Required env vars:
      MAPPING      Path to IdP export JSON { users:[{uid,email,name}...],
                   organizations:[{id,name,slug}...] }
      ECHO_ORG_ID  IdP UUID of the ECHO organization (must be in mapping)

    Optional env vars:
      DRY_RUN      '1' (default) = report only; '0' = write
      BATCH_SIZE   Records per transaction batch (default 500)
  DESC
  task backfill: :environment do
    mapping_path = ENV.fetch('MAPPING', nil)
    echo_org_id  = ENV.fetch('ECHO_ORG_ID', nil)
    dry_run      = ENV.fetch('DRY_RUN', '1') != '0'
    batch_size   = ENV.fetch('BATCH_SIZE', '500').to_i

    abort 'ERROR: MAPPING env var is required' if mapping_path.blank?
    abort 'ERROR: ECHO_ORG_ID env var is required' if echo_org_id.blank?

    puts 'ownership:backfill starting'
    puts "  DRY_RUN=#{dry_run ? '1 (no writes)' : '0 (WRITING)'}"
    puts "  MAPPING=#{mapping_path}"
    puts "  ECHO_ORG_ID=#{echo_org_id}"
    puts "  BATCH_SIZE=#{batch_size}"
    puts

    backfill = OwnershipBackfill.new(
      mapping_path: mapping_path,
      echo_org_id: echo_org_id,
      dry_run: dry_run,
      batch_size: batch_size
    )

    report = backfill.run
    puts report
  rescue ArgumentError => e
    abort "ERROR: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # ownership:verify
  # ---------------------------------------------------------------------------
  desc <<~DESC
    Read-only invariant check. Exits with code 1 on any violation.
    Run after ownership:backfill to confirm the backfill succeeded.
  DESC
  task verify: :environment do
    puts 'ownership:verify'
    puts '=' * 60

    violations = []

    owned_models = [Plant, Variety, Specimen, Location, Category]

    # 1. Missing ownership columns
    owned_models.each do |model|
      %i[owner_organization_id source_organization_id created_by_principal_id].each do |col|
        missing = model.where(col => nil).count
        if missing.positive?
          sample_ids = model.where(col => nil).limit(5).pluck(:id)
          violations << "#{model.table_name}: #{missing} rows missing #{col} (first 5: #{sample_ids.join(', ')})"
        end
      end

      # 2. deleted_at invariant: rows with visibility=deleted (integer 3) must
      #    have deleted_at set. A NULL deleted_at on a deleted row means the
      #    backfill never ran or was corrupted -- flag it explicitly.
      missing_deleted_at = model.where(visibility: 3).where(deleted_at: nil).count
      if missing_deleted_at.positive?
        sample_ids = model.where(visibility: 3).where(deleted_at: nil).limit(5).pluck(:id)
        violations << "#{model.table_name}: #{missing_deleted_at} rows have visibility=deleted " \
                      "but deleted_at IS NULL (first 5: #{sample_ids.join(', ')})"
      end

      # 3. Facade/column disagreement: VisibilityBridge.visibility_for(trio) != stored visibility
      disagreements = []
      model.where.not(publication_state: nil).find_each do |record|
        derived = VisibilityBridge.visibility_for(
          publication_state: record.publication_state,
          access_level: record.access_level,
          deleted_at: record.deleted_at
        )
        disagreements << record.id if derived != record.visibility.to_sym
      end
      if disagreements.any?
        violations << "#{model.table_name}: #{disagreements.size} rows with facade/column disagreement " \
                      "(first 5: #{disagreements.first(5).join(', ')})"
      end
    end

    # 4. Organization kind shape invariant check (raw SQL mirrors the CHECK constraint)
    #    kind='real' requires external_idp_id NOT NULL and principal_id IS NULL
    #    kind='personal' requires principal_id NOT NULL and external_idp_id IS NULL
    invalid_real = Organization.where(kind: 'real')
                               .where('external_idp_id IS NULL OR principal_id IS NOT NULL')
                               .count
    violations << "organizations: #{invalid_real} 'real' orgs violate kind shape" if invalid_real.positive?

    invalid_personal = Organization.where(kind: 'personal')
                                   .where('principal_id IS NULL OR external_idp_id IS NOT NULL')
                                   .count
    violations << "organizations: #{invalid_personal} 'personal' orgs violate kind shape" if invalid_personal.positive?

    # 5. Records whose owner_organization_id points at a missing org
    #    (FK constraint makes this impossible in practice -- noted in output)
    puts '  NOTE: FK constraint on owner_organization_id -> organizations prevents orphaned org refs.'

    # 6. Principals with duplicate (issuer, external_uid)
    #    (unique partial index makes this impossible -- noted in output)
    puts '  NOTE: Unique partial index on (identity_issuer, external_uid) WHERE external_uid IS NOT NULL'
    puts '        prevents duplicate principal entries.'

    # 7. Owned records whose owner_organization_id refers to an org with kind=nil
    #    (sanity check: count service-principal orgs, which don't exist by design)
    service_owned = 0
    owned_models.each do |model|
      service_owned += model
                       .joins("JOIN organizations ON organizations.id = #{model.table_name}.owner_organization_id")
                       .where(organizations: { kind: nil })
                       .count
    end
    violations << "#{service_owned} records owned by orgs with nil kind" if service_owned.positive?

    puts
    if violations.empty?
      puts 'PASS: All invariants satisfied.'
    else
      puts "FAIL: #{violations.size} violation(s):"
      violations.each { |v| puts "  - #{v}" }
      exit 1
    end
    puts '=' * 60
  end

  # ---------------------------------------------------------------------------
  # ownership:report
  # ---------------------------------------------------------------------------
  desc <<~DESC
    Read-only stats report for operator dashboards during rollout.
    Shows record counts per organization, publication_state, access_level,
    soft-delete counts, and unfilled column counts.
  DESC
  task report: :environment do
    puts 'ownership:report'
    puts '=' * 60

    owned_models = [Plant, Variety, Specimen, Location, Category]

    # --- Per publication_state / access_level ---
    puts "\nPUBLICATION STATE / ACCESS LEVEL"
    owned_models.each do |model|
      puts "  #{model.table_name}:"
      model.group(:publication_state, :access_level).count.each do |(ps, al), count|
        puts "    #{ps || '(nil)'} / #{al || '(nil)'}: #{count}"
      end
    end

    # --- Soft-deleted counts ---
    puts "\nSOFT-DELETED RECORDS (deleted_at IS NOT NULL)"
    owned_models.each do |model|
      deleted = model.where.not(deleted_at: nil).count
      puts "  #{model.table_name}: #{deleted}"
    end

    # --- Unfilled counts ---
    puts "\nUNFILLED (owner_organization_id IS NULL)"
    owned_models.each do |model|
      unfilled = model.where(owner_organization_id: nil).count
      puts "  #{model.table_name}: #{unfilled}"
    end

    # --- Per-organization record counts ---
    puts "\nRECORDS PER OWNER ORGANIZATION (top 20 orgs)"
    org_counts = {}
    owned_models.each do |model|
      model.where.not(owner_organization_id: nil)
           .group(:owner_organization_id).count.each do |org_id, count|
        org_counts[org_id] ||= 0
        org_counts[org_id] += count
      end
    end
    org_ids = org_counts.keys
    orgs_by_id = Organization.where(id: org_ids).index_by(&:id)
    org_counts.sort_by { |_, c| -c }.first(20).each do |org_id, count|
      org = orgs_by_id[org_id]
      label = org ? "#{org.name} (#{org.kind})" : org_id.to_s
      puts "  #{label}: #{count} records"
    end

    # --- Legacy visibility distribution ---
    puts "\nLEGACY VISIBILITY DISTRIBUTION"
    owned_models.each do |model|
      puts "  #{model.table_name}: #{model.group(:visibility).count.inspect}"
    end

    # --- Principal + org counts ---
    puts "\nPRINCIPALS"
    Principal.group(:kind).count.each { |k, c| puts "  #{k}: #{c}" }
    puts "\nORGANIZATIONS"
    Organization.group(:kind).count.each { |k, c| puts "  #{k}: #{c}" }

    puts '=' * 60
  end
end
