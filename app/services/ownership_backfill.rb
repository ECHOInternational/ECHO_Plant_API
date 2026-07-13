# frozen_string_literal: true

# Backfills the Phase B ownership/publication columns (owner_organization_id,
# source_organization_id, created_by_principal_id, publication_state,
# access_level, deleted_at) for the five independently-owned tables (plants,
# varieties, specimens, locations, categories).
#
# Design constraints:
#   - Idempotent and resumable: rows already filled are skipped.
#   - Per-batch transactions: each BATCH_SIZE chunk commits independently so a
#     failure is resumable without restarting from scratch.
#   - PaperTrail DISABLED during backfill writes (PaperTrail.request.disable_model)
#     to avoid creating ~20k version rows for mechanical column population.
#     This is deliberate and documented in the report output.
#   - update_columns is used (skips validations AND callbacks). This is required
#     because the OrganizedResource dual-write callback would conflict with the
#     explicit trio being set here for deleted rows (visibility=deleted but we
#     must write publication_state/access_level as the restoration default, not
#     recompute from scratch). Explicitly documented.
#   - A round-trip guard verifies every row: VisibilityBridge.visibility_for
#     applied to the derived trio must equal the record's current visibility
#     symbol. Rows that fail the guard are refused (counted, reported, NOT
#     written).
#   - DRY_RUN=1 (default) prints the full report but writes nothing.
#
# Usage:
#   rake ownership:backfill MAPPING=/path/to/mapping.json ECHO_ORG_ID=<uuid>
#   rake ownership:backfill MAPPING=... ECHO_ORG_ID=... DRY_RUN=0
class OwnershipBackfill
  SHARED_EMAILS = %w[echo@echonet.org sandbox@sandbox.com].freeze
  ECHOCOMMUNITY_ISSUER = 'https://www.echocommunity.org'

  # Owned tables processed by this backfill (NOT images -- they inherit).
  OWNED_MODELS = [Plant, Variety, Specimen, Location, Category].freeze

  # Lightweight stub used in dry-run mode to avoid database writes while still
  # letting the rest of the logic reference .id, .kind, etc.
  DryRunStub = Struct.new(:id, :email, :kind, :external_uid, keyword_init: true) do
    def dry_run_stub?
      true
    end
  end

  Report = Struct.new(
    :dry_run,
    :principals_created_human,
    :principals_created_service,
    :principals_legacy_unmapped,
    :unmapped_emails,
    :orgs_created_personal,
    :orgs_created_echo,
    :table_stats,          # Hash[table_name => { total:, filled:, skipped:, refused: }]
    :refused_rows,         # Array of { table:, id:, reason: }
    :anomalies,            # Array of strings
    keyword_init: true
  ) do
    def initialize(*)
      super
      self.table_stats              ||= {}
      self.refused_rows             ||= []
      self.anomalies                ||= []
      self.unmapped_emails          ||= []
      self.principals_created_human   ||= 0
      self.principals_created_service ||= 0
      self.principals_legacy_unmapped ||= 0
      self.orgs_created_personal      ||= 0
      self.orgs_created_echo          ||= 0
    end

    def to_s # rubocop:disable Metrics/MethodLength
      lines = []
      lines << ('=' * 60)
      lines << 'OWNERSHIP BACKFILL REPORT'
      lines << "  DRY_RUN: #{dry_run ? 'YES (no writes performed)' : 'NO (data written)'}"
      lines << '  NOTE: PaperTrail disabled during backfill writes to avoid'
      lines << '        generating ~20k version rows for mechanical column population.'
      lines << '  NOTE: update_columns used (bypasses callbacks) to prevent the'
      lines << '        OrganizedResource dual-write callback from overriding the'
      lines << '        explicit publication_state/access_level set for deleted rows.'
      lines << ('-' * 60)
      lines << 'PRINCIPALS'
      lines << "  Created (human, IdP-mapped): #{principals_created_human}"
      lines << "  Created (service, shared emails): #{principals_created_service}"
      lines << "  Created (legacy, unmapped): #{principals_legacy_unmapped}"
      if unmapped_emails.any?
        lines << '  Unmapped email list:'
        unmapped_emails.each { |e| lines << "    - #{e}" }
      end
      lines << 'ORGANIZATIONS'
      lines << "  ECHO org created/found: #{orgs_created_echo}"
      lines << "  Personal orgs created: #{orgs_created_personal}"
      lines << ('-' * 60)
      lines << 'TABLE STATS'
      table_stats.each do |table, s|
        lines << "  #{table}: total=#{s[:total]} filled=#{s[:filled]} " \
                 "skipped_already_filled=#{s[:skipped]} refused=#{s[:refused]}"
      end
      if refused_rows.any?
        lines << 'REFUSED ROWS (round-trip guard failures)'
        refused_rows.first(20).each do |r|
          lines << "  #{r[:table]}##{r[:id]}: #{r[:reason]}"
        end
        lines << "  ... (#{refused_rows.size} total)" if refused_rows.size > 20
      end
      if anomalies.any?
        lines << 'ANOMALIES'
        anomalies.each { |a| lines << "  #{a}" }
      end
      lines << ('=' * 60)
      lines.join("\n")
    end
  end

  def initialize(mapping_path:, echo_org_id:, dry_run: true, batch_size: 500)
    @mapping_path = mapping_path
    @echo_org_id  = echo_org_id
    @dry_run      = dry_run
    @batch_size   = batch_size
    @report       = Report.new(dry_run: dry_run)
  end

  # Runs the full backfill pipeline. Returns the completed Report.
  def run
    mapping = load_mapping!
    validate_mapping!(mapping)

    email_to_uid, uid_to_entry = build_lookup_tables(mapping)

    echo_org = find_or_create_echo_org!(mapping, @echo_org_id)
    principal_cache = build_principal_cache(email_to_uid, uid_to_entry, echo_org)

    OWNED_MODELS.each do |model|
      backfill_model!(model, principal_cache, echo_org)
    end

    @report
  end

  private

  # --- Mapping load + validation ---

  def load_mapping!
    raise ArgumentError, 'MAPPING env var is required' if @mapping_path.blank?
    raise ArgumentError, "MAPPING file not found: #{@mapping_path}" unless File.exist?(@mapping_path)

    JSON.parse(File.read(@mapping_path))
  rescue JSON::ParserError => e
    raise ArgumentError, "MAPPING file is not valid JSON: #{e.message}"
  end

  def validate_mapping!(mapping)
    users = mapping['users']
    orgs  = mapping['organizations']

    raise ArgumentError, "mapping.json must have a 'users' array" unless users.is_a?(Array)
    raise ArgumentError, "mapping.json must have an 'organizations' array" unless orgs.is_a?(Array)

    # Abort on blank uid or email
    users.each_with_index do |u, i|
      raise ArgumentError, "users[#{i}] has blank uid"   if u['uid'].blank?
      raise ArgumentError, "users[#{i}] has blank email" if u['email'].blank?
    end

    # Abort on duplicate uids
    uids = users.map { |u| u['uid'] }
    dup_uids = uids.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    raise ArgumentError, "Duplicate uids in mapping: #{dup_uids.join(', ')}" if dup_uids.any?

    # Abort on duplicate emails mapped to multiple uids
    emails = users.map { |u| u['email'] }
    dup_emails = emails.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    raise ArgumentError, "Duplicate emails in mapping: #{dup_emails.join(', ')}" if dup_emails.any?

    # Validate ECHO_ORG_ID present in organizations list
    org_ids = orgs.map { |o| o['id'] }
    return if org_ids.include?(@echo_org_id)

    raise ArgumentError,
          "ECHO_ORG_ID '#{@echo_org_id}' not found in mapping organizations list"
  end

  def build_lookup_tables(mapping)
    # email -> uid (for humans in the mapping)
    email_to_uid = mapping['users'].to_h { |u| [u['email'], u['uid']] }
    # uid -> full entry
    uid_to_entry = mapping['users'].to_h { |u| [u['uid'], u] }
    [email_to_uid, uid_to_entry]
  end

  # --- Org creation ---

  def find_or_create_echo_org!(mapping, echo_org_id)
    org_entry = mapping['organizations'].find { |o| o['id'] == echo_org_id }
    raise ArgumentError, 'ECHO_ORG_ID not found in mapping' unless org_entry

    if @dry_run
      # Return a mock-like struct so the rest of the code can reference .id
      existing = Organization.find_by(external_idp_id: echo_org_id)
      if existing
        @report.orgs_created_echo += 0 # found, not created
        return existing
      end
      # Not yet persisted in dry run -- return a stub
      @report.orgs_created_echo += 1
      return DryRunStub.new(id: echo_org_id, email: nil, kind: 'real', external_uid: nil)
    end

    org = Organization.mirror_real!(external_id: echo_org_id, name: org_entry['name'])
    @report.orgs_created_echo += 1
    org
  end

  # --- Principal cache ---

  # Returns a hash { email => principal } for every distinct email across all
  # owned tables. Shared emails -> service principals, mapped -> resolved!,
  # unmapped -> legacy_for_email.
  def build_principal_cache(email_to_uid, uid_to_entry, _echo_org)
    all_emails = collect_all_emails
    cache = {}

    all_emails.each do |email|
      principal = if SHARED_EMAILS.include?(email)
                    resolve_service_principal(email)
                  elsif email_to_uid.key?(email)
                    resolve_human_principal(email, email_to_uid[email], uid_to_entry)
                  else
                    @report.unmapped_emails << email unless @report.unmapped_emails.include?(email)
                    resolve_legacy_principal(email)
                  end
      cache[email] = principal
    end

    # Create personal orgs for all HUMAN principals (not service)
    cache.each_value do |principal|
      next if principal.nil?
      next if principal.respond_to?(:dry_run_stub?) && principal.dry_run_stub?
      next unless principal.kind == 'human'

      create_personal_org_for!(principal)
    end

    cache
  end

  def collect_all_emails
    emails = Set.new
    OWNED_MODELS.each do |model|
      # Use pluck to avoid loading full objects
      model.pluck(:owned_by, :created_by).each do |(ob, cb)|
        emails << ob  if ob.present?
        emails << cb  if cb.present?
      end
    end
    emails.to_a
  end

  def resolve_service_principal(email)
    if @dry_run
      existing = Principal.find_by(identity_issuer: 'legacy-shared', email: email) ||
                 Principal.where(kind: 'service', email: email).first
      return existing if existing

      @report.principals_created_service += 1
      return dry_run_stub(email: email, kind: 'service')
    end

    created = false
    principal = Principal.find_or_create_by!(
      identity_issuer: 'legacy-shared',
      email: email
    ) do |p|
      p.kind         = 'service'
      p.external_uid = nil
      p.display_name = "Shared service account (#{email})"
      created = true
    end
    @report.principals_created_service += 1 if created
    principal
  rescue ActiveRecord::RecordNotUnique
    Principal.find_by!(identity_issuer: 'legacy-shared', email: email)
  end

  def resolve_human_principal(email, uid, uid_to_entry)
    entry = uid_to_entry[uid]

    if @dry_run
      existing = Principal.find_by(identity_issuer: ECHOCOMMUNITY_ISSUER, external_uid: uid)
      return existing if existing

      @report.principals_created_human += 1
      return dry_run_stub(email: email, kind: 'human', external_uid: uid)
    end

    was_new = !Principal.exists?(identity_issuer: ECHOCOMMUNITY_ISSUER, external_uid: uid)
    principal = Principal.resolve!(
      issuer: ECHOCOMMUNITY_ISSUER,
      external_uid: uid,
      email: email,
      display_name: entry['name']
    )
    @report.principals_created_human += 1 if was_new
    principal
  end

  def resolve_legacy_principal(email)
    if @dry_run
      existing = Principal.find_by(identity_issuer: Principal::LEGACY_ISSUER, email: email)
      return existing if existing

      @report.principals_legacy_unmapped += 1
      return dry_run_stub(email: email, kind: 'human')
    end

    was_new = !Principal.exists?(identity_issuer: Principal::LEGACY_ISSUER, email: email)
    principal = Principal.legacy_for_email(email)
    @report.principals_legacy_unmapped += 1 if was_new
    principal
  end

  def create_personal_org_for!(principal)
    if @dry_run
      existing = Organization.find_by(principal_id: principal.id)
      @report.orgs_created_personal += 1 if existing.nil?
      return
    end

    existing = Organization.find_by(principal_id: principal.id)
    return if existing

    Organization.personal_for!(principal)
    @report.orgs_created_personal += 1
  end

  # --- Per-model backfill ---

  def backfill_model!(model, principal_cache, echo_org)
    table_name = model.table_name
    stats = { total: 0, filled: 0, skipped: 0, refused: 0 }

    # Only fetch rows where the new columns are nil (resumable)
    scope = model.where(owner_organization_id: nil)
    stats[:total] = model.count
    stats[:skipped] = model.where.not(owner_organization_id: nil).count

    scope.find_in_batches(batch_size: @batch_size) do |batch|
      process_batch!(batch, model, principal_cache, echo_org, stats)
    end

    @report.table_stats[table_name] = stats
  end

  def process_batch!(batch, model, principal_cache, echo_org, stats) # rubocop:disable Metrics/MethodLength
    rows_to_write = []

    batch.each do |record|
      attrs = build_ownership_attrs(record, principal_cache, echo_org)
      if attrs.nil?
        stats[:refused] += 1
        @report.refused_rows << {
          table: model.table_name,
          id: record.id,
          reason: 'Could not derive ownership attributes (missing principal or org)'
        }
        next
      end

      # Round-trip guard: verify the derived trio maps back to the record's
      # current visibility. For deleted rows, deleted_at must be non-nil.
      unless round_trip_ok?(record, attrs)
        stats[:refused] += 1
        @report.refused_rows << {
          table: model.table_name,
          id: record.id,
          reason: "Round-trip guard failed: visibility=#{record.visibility}, " \
                  "derived trio={#{attrs[:publication_state]}/#{attrs[:access_level]}" \
                  "/deleted_at:#{attrs[:deleted_at].inspect}}"
        }
        next
      end

      rows_to_write << [record, attrs]
      stats[:filled] += 1
    end

    write_batch!(rows_to_write) unless @dry_run
  end

  def build_ownership_attrs(record, principal_cache, echo_org)
    owned_by_email   = record.owned_by
    created_by_email = record.created_by

    owner_principal   = principal_cache[owned_by_email]
    creator_principal = principal_cache[created_by_email]

    return nil if owner_principal.nil? || creator_principal.nil?

    owner_org_id = if SHARED_EMAILS.include?(owned_by_email)
                     echo_org.id
                   elsif @dry_run && owner_principal.respond_to?(:dry_run_stub?) && owner_principal.dry_run_stub?
                     # Dry run: stub personal org id
                     "dryrun-personal-org-for-#{owned_by_email}"
                   else
                     personal_org_id_for(owner_principal)
                   end

    return nil if owner_org_id.nil?

    trio = derive_trio(record)
    return nil if trio.nil?

    {
      owner_organization_id: owner_org_id,
      source_organization_id: owner_org_id,
      created_by_principal_id: @dry_run && creator_principal.respond_to?(:dry_run_stub?) && creator_principal.dry_run_stub? ? SecureRandom.uuid : creator_principal.id,
      publication_state: trio[:publication_state],
      access_level: trio[:access_level],
      deleted_at: trio[:deleted_at]
    }
  end

  def personal_org_id_for(principal)
    return nil if principal.nil?
    return principal.id if principal.respond_to?(:dry_run_stub?) && principal.dry_run_stub?

    Organization.find_by(principal_id: principal.id)&.id
  end

  # Derives the trio (publication_state, access_level, deleted_at) from the
  # record's current visibility. For :deleted, the trio is set to the
  # restoration default (published/organization) so a restore is meaningful,
  # and deleted_at is set to record.updated_at as the best available
  # approximation of when deletion occurred.
  #
  # NOTE: deleted_at is approximated from updated_at because the legacy schema
  # has no explicit deletion timestamp. This is documented in the report.
  def derive_trio(record)
    vis = record.visibility.to_sym
    if vis == :deleted
      # Restoration default: published/organization (matches the design spec).
      # deleted_at approximated from updated_at (best available; documented).
      {
        publication_state: 'published',
        access_level: 'organization',
        deleted_at: record.updated_at
      }
    else
      trio = VisibilityBridge.trio_for(vis)
      return nil if trio.nil?

      trio.merge(deleted_at: nil)
    end
  end

  # Verifies the derived trio round-trips back to the record's stored visibility.
  def round_trip_ok?(record, attrs)
    derived_vis = VisibilityBridge.visibility_for(
      publication_state: attrs[:publication_state],
      access_level: attrs[:access_level],
      deleted_at: attrs[:deleted_at]
    )
    derived_vis == record.visibility.to_sym
  end

  def write_batch!(rows_to_write)
    return if rows_to_write.empty?

    # PaperTrail is disabled for these writes to avoid creating ~20k version
    # rows for mechanical column population. This is documented in the report.
    PaperTrail.request(enabled: false) do
      ActiveRecord::Base.transaction do
        rows_to_write.each do |record, attrs|
          record.update_columns(attrs)
        end
      end
    end
  end

  # Returns a minimal duck-type stub used in dry-run mode to avoid writing to
  # the database while still allowing the rest of the logic to proceed.
  def dry_run_stub(email:, kind:, external_uid: nil)
    DryRunStub.new(
      id: SecureRandom.uuid,
      email: email,
      kind: kind,
      external_uid: external_uid
    )
  end
end
