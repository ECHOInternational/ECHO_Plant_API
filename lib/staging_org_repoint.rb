# frozen_string_literal: true

# Re-points STAGING ownership from one organization id to another, so staging
# follows the production identity model: one organization, one id, shared by
# ECHOcommunity (the IdP, which creates it) and this API (whose mirrored real
# organizations adopt the IdP UUID as their local primary key; see
# Organization.mirror_real! and docs/ownership-redesign/design.md section 2).
#
# Staging was built with placeholder ids instead (the S7 rehearsal's ECHO org
# and production's FPI id), so ECHOcommunity staging's projection could not
# match them to its own organizations. Option B, chosen 2026-10-23, moves the
# staging data onto the ECHOcommunity staging ids. STAGING_MAPPING holds them.
#
# For each from -> to pair, in ONE transaction:
#   1. lock the source organization row;
#   2. adopt the target row if it exists (a login with an organizations claim
#      mirrors it), or create it the way mirror_real! would (id ==
#      external_idp_id, kind real), copying the source's name until the next
#      login refreshes it from the claim;
#   3. move every column with a foreign key to organizations.id (discovered
#      from the catalog, so a new reference is never silently left behind);
#   4. check nothing still references the source, then delete the source row.
#
# What it deliberately does not do:
#   * touch updated_at: ownership moved, content did not, and bumping it would
#     make every plants(updatedSince:) client re-download ~33,000 plants;
#   * write PaperTrail versions for the moved rows (update_all) or rewrite old
#     ones: history stays as it was recorded. Old versions that name the source
#     id render as "Unknown organization" in the change history once the row is
#     gone; their count is reported.
#
# Idempotent: a pair whose source row is gone and whose target row exists is
# reported as already re-pointed and skipped. Reverse (rollback) is the same
# operation with the mapping inverted. It is exact unless the target owned
# rows of its own before the forward run (reported as target_rows_before):
# the reverse moves everything the target owns.
#
# Prints ids and counts only, never a name or an email.
# rubocop:disable Metrics/ClassLength -- a one-off ops tool kept in one file so
# the guards, the mapping rules and the move are reviewed together.
class StagingOrgRepoint
  STAGING_DATABASE = 'Plant_API_staging'
  CONFIRM_VALUE = 'REPOINT-STAGING-ORGS'

  # API staging placeholder id => ECHOcommunity staging organization id.
  STAGING_MAPPING = {
    # ECHO: the S7 rehearsal's placeholder => ECHOcommunity staging "echo".
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0001' => '149f6971-b63a-45e7-be7f-e67fc7d7b3d6',
    # Food Plants International: production's id => ECHOcommunity staging
    # "food-plants-international".
    'b7ab3117-e610-4b7d-b097-a51ebe911d79' => 'ad8f2875-2bd5-46fb-b514-9f6becf47ad4'
  }.freeze

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  class Refused < StandardError; end

  Result = Struct.new(:from, :to, :status, :target_created, :target_rows_before, :moved,
                      :versions_mentioning, keyword_init: true)

  # The class-level surface: discovery, guards and mapping parsing.
  module Setup
    # Every (table, column) with a foreign key to organizations(id).
    def references(connection)
      connection.select_rows(<<~SQL).map { |table, column| [table, column] }.sort
        SELECT rel.relname, att.attname
          FROM pg_constraint con
          JOIN pg_class rel ON rel.oid = con.conrelid
          JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
          JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY (con.conkey)
         WHERE con.contype = 'f'
           AND con.confrelid = 'organizations'::regclass
           AND nsp.nspname = current_schema()
      SQL
    end

    def guard!(apply:, confirm:, env: Rails.env, connection: ActiveRecord::Base.connection)
      refuse!('RAILS_ENV is production. This tool rewrites ownership and runs on staging only.') if env.to_s == 'production'

      database = connection.current_database
      refuse!("runs only against #{STAGING_DATABASE}. Connected to: #{database.inspect}") if database != STAGING_DATABASE
      refuse!("APPLY=true also needs CONFIRM=#{CONFIRM_VALUE}") if apply && confirm != CONFIRM_VALUE
    end

    # MAPPING="from:to,from:to", or FROM= and TO= for one pair, or the built-in
    # STAGING_MAPPING. REVERSE=true inverts whichever was chosen.
    def mapping_from_env(env)
      from = env['FROM'].presence
      to = env['TO'].presence
      raise Refused, 'FROM and TO must be given together' if from.nil? ^ to.nil?

      mapping =
        if from then parse_mapping("#{from}:#{to}")
        elsif env['MAPPING'].present? then parse_mapping(env['MAPPING'])
        else STAGING_MAPPING
        end
      env['REVERSE'] == 'true' ? invert(mapping) : mapping
    end

    def parse_mapping(raw)
      pairs = raw.to_s.split(',').map { |pair| parse_pair(pair) }
      raise Refused, 'empty mapping' if pairs.empty?

      validate!(pairs)
      pairs.to_h.freeze
    end

    def invert(mapping)
      mapping.invert.freeze
    end

    private

    def refuse!(message)
      raise Refused, "REFUSING: #{message}"
    end

    def parse_pair(pair)
      from, to = pair.split(':', 2).map { |id| id.to_s.strip.downcase }
      [from, to].each { |id| raise Refused, "malformed organization id: #{id.inspect}" unless UUID.match?(id) }
      raise Refused, "#{from} is mapped to itself" if from == to

      [from, to]
    end

    def validate!(pairs)
      froms = pairs.map(&:first)
      tos = pairs.map(&:last)
      raise Refused, 'an id appears more than once as a source' if froms.uniq.size != froms.size
      raise Refused, 'an id appears more than once as a target' if tos.uniq.size != tos.size

      both = froms & tos
      raise Refused, "#{both.join(', ')} is both a source and a target (no chains)" if both.any?
    end
  end
  extend Setup

  def initialize(mapping:, apply:, out: $stdout, connection: ActiveRecord::Base.connection)
    @mapping = mapping
    @apply = apply
    @out = out
    @connection = connection
  end

  def run
    @out.puts "#{@apply ? 'APPLYING' : 'DRY RUN'} organization re-point (#{@mapping.size} pair(s))"
    results = @mapping.map { |from, to| repoint(from, to) }
    @out.puts @apply ? 'Done.' : 'DRY RUN only: nothing was written. Re-run with APPLY=true CONFIRM=...'
    results
  end

  private

  def repoint(from, to)
    result = Organization.transaction do
      source = Organization.lock.find_by(id: from)
      target = Organization.find_by(id: to)
      check!(from, to, source, target)

      if source.nil?
        already_done(from, to)
      else
        move(source, target, to)
      end
    end
    report(result)
    result
  end

  def check!(from, to, source, target)
    raise Refused, "neither #{from} nor #{to} exists in organizations" if source.nil? && target.nil?
    raise Refused, "#{from} is a personal organization; only real organizations are re-pointed" if personal?(source)
    raise Refused, "target #{to} exists but is not a mirrored real organization" unless mirrored_or_absent?(target, to)

    squatter = Organization.where(external_idp_id: to).where.not(id: to).pick(:id)
    raise Refused, "organization #{squatter} already has external_idp_id #{to} under a different id" if squatter
  end

  def personal?(org) = org.present? && org.kind != 'real'

  # A mirrored real organization's id IS its IdP id (Organization.mirror_real!).
  def mirrored_or_absent?(org, id) = org.nil? || (org.kind == 'real' && org.external_idp_id == id)

  def already_done(from, to)
    Result.new(from: from, to: to, status: :already_repointed, target_created: false,
               target_rows_before: count_references(to).values.sum,
               moved: count_references(from), versions_mentioning: versions_mentioning(from))
  end

  def move(source, target, to)
    result = Result.new(from: source.id, to: to, status: :would_repoint, target_created: false,
                        target_rows_before: count_references(to).values.sum,
                        moved: count_references(source.id), versions_mentioning: versions_mentioning(source.id))
    apply_move!(source, target, result) if @apply
    result
  end

  # Any failure raises, and the surrounding transaction rolls the whole pair
  # back: the target row, every moved column, and the retirement.
  def apply_move!(source, target, result)
    result.target_created = target.nil?
    create_target!(source, result.to) if target.nil?

    verify_moved!(source.id, result.moved, update_references!(source.id, result.to))
    retire!(source)
    result.status = :repointed
  end

  def verify_moved!(from, planned, moved)
    raise ActiveRecord::ActiveRecordError, "moved #{moved} but planned #{planned}" unless moved == planned

    leftover = count_references(from).values.sum
    raise ActiveRecord::ActiveRecordError, "#{leftover} references to #{from} remain" unless leftover.zero?
  end

  def create_target!(source, to)
    Organization.create!(id: to, external_idp_id: to, kind: 'real', name: source.name)
  end

  def retire!(source)
    source.destroy!
  end

  def update_references!(from, to)
    self.class.references(@connection).to_h do |table, column|
      sql = "UPDATE #{quote_table(table)} SET #{quote_column(column)} = #{@connection.quote(to)} " \
            "WHERE #{quote_column(column)} = #{@connection.quote(from)}"
      ["#{table}.#{column}", @connection.update(sql)]
    end
  end

  def count_references(org_id)
    self.class.references(@connection).to_h do |table, column|
      count = @connection.select_value(
        "SELECT count(*) FROM #{quote_table(table)} WHERE #{quote_column(column)} = #{@connection.quote(org_id)}"
      ).to_i
      ["#{table}.#{column}", count]
    end
  end

  # PaperTrail rows whose serialized object, changes or metadata name the id.
  # Reported, never rewritten.
  def versions_mentioning(org_id)
    pattern = @connection.quote("%#{org_id}%")
    @connection.select_value(<<~SQL).to_i
      SELECT count(*) FROM versions
       WHERE object LIKE #{pattern} OR object_changes LIKE #{pattern} OR metadata::text LIKE #{pattern}
    SQL
  end

  def quote_table(name) = @connection.quote_table_name(name)
  def quote_column(name) = @connection.quote_column_name(name)

  def report(result)
    verb = verb_for(result)
    lines = ["#{result.from} -> #{result.to}: #{result.status}",
             "  target organization row: #{target_line(result)}",
             "  target already referenced by #{result.target_rows_before} row-column(s) before this run"]
    lines += result.moved.map { |ref, count| "  #{verb} #{ref}: #{count}" }
    lines << "  #{verb} total: #{result.moved.values.sum}"
    lines << "  versions naming #{result.from} (left as recorded): #{result.versions_mentioning}"
    @out.puts lines
  end

  def verb_for(result) = result.status == :would_repoint ? 'would move' : 'moved'

  def target_line(result)
    case result.status
    when :already_repointed then 'exists (source row already retired; nothing to do)'
    when :would_repoint then Organization.exists?(result.to) ? 'exists, would be adopted' : 'would be created'
    else result.target_created ? 'created' : 'existed, adopted'
    end
  end
end
# rubocop:enable Metrics/ClassLength
