# frozen_string_literal: true

# Writes the family rows produced by CatalogueOfLife into the families table.
#
# Extracted out of lib/tasks/families.rake (which is now a thin CLI wrapper)
# so the part that actually touches the database has an automated regression
# test. That part broke once already in real life: see the note on
# +REFRESHABLE_ATTRIBUTES+ and +write!+ below.
class FamilySeeder
  Report = Struct.new(
    :dry_run,
    :fetched,
    :by_kingdom,
    :unmapped,
    :new_count,
    :existing_count,
    :family_count, # nil in dry-run mode: nothing was written, so it would be misleading
    keyword_init: true
  ) do
    def to_s
      lines = ["Fetched #{fetched} families."]
      lines << "WARNING: #{unmapped} families have no plant type mapping." if unmapped.positive?
      by_kingdom.each { |k, n| lines << format('  %<kingdom>-10s %<count>5d', kingdom: k, count: n) }
      lines << ''
      lines << "#{new_count} new, #{existing_count} already present."
      lines.concat(closing_lines)
      lines.join("\n")
    end

    private

    def closing_lines
      return ['', 'DRY RUN. Re-run with DRY_RUN=0 to write.'] if dry_run

      ["Done. #{family_count} families in the table."]
    end
  end

  # Attributes refreshed on every upsert, insert or update alike. Deliberately
  # excludes translations and every curator-editable column (description,
  # seed_banking_notes, storage_physiology, seed_longevity, seed_banking_rank
  # -- see FamilyPolicy and Family::STORAGE_PHYSIOLOGIES et al.): a re-seed
  # must refresh the taxonomic facts sourced from COL without ever destroying
  # content a human curator wrote. Covered by spec/services/family_seeder_spec.rb.
  REFRESHABLE_ATTRIBUTES = %i[col_id kingdom plant_type classification_version snapshot_date].freeze

  def initialize(client: CatalogueOfLife.new, version: CatalogueOfLife::DEFAULT_VERSION,
                 snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT, dry_run: true)
    @client = client
    @version = version
    @snapshot_date = snapshot_date
    @dry_run = dry_run
  end

  def run
    rows = @client.all_families
    # existing/new_count MUST be computed before write!: they report what was
    # true walking in, not what upsert_all just made true. Computing this
    # after the write would make new_count always read 0 on a live run.
    existing = Family.pluck(:name).to_set(&:downcase)
    new_count = rows.count { |r| !existing.include?(r[:name].downcase) }

    write!(rows) unless @dry_run

    build_report(rows, new_count)
  end

  private

  def build_report(rows, new_count)
    Report.new(
      dry_run: @dry_run,
      fetched: rows.size,
      by_kingdom: rows.group_by { |r| r[:kingdom] }.transform_values(&:size),
      unmapped: rows.count { |r| r[:plant_type].nil? },
      new_count: new_count,
      existing_count: rows.size - new_count,
      family_count: @dry_run ? nil : Family.count
    )
  end

  def write!(rows)
    now = Time.current
    # translations is deliberately omitted from the merged row below: an
    # explicit translations: {} looks inert but is not.
    # ActiveRecord::Type::Serialized#serialize collapses a hash equal to the
    # Mobility container coder's own "empty" value to nil rather than "{}", so
    # upsert_all would write a literal SQL NULL for a NOT NULL jsonb column.
    # Omitting the key lets every INSERT fall through to the column's own
    # DEFAULT '{}' instead. Regression-tested: see the "insert half" example
    # in spec/services/family_seeder_spec.rb.
    attributes = rows.map do |row|
      row.merge(
        status: 'accepted',
        classification_source: 'catalogue-of-life',
        classification_version: @version,
        snapshot_date: @snapshot_date,
        created_at: now,
        updated_at: now
      )
    end

    # upsert_all rather than the one-row-at-a-time style used by db/seeds.rb:
    # 4,596 rows through ActiveRecord with Mobility callbacks is needlessly
    # slow, and upserting is what makes a re-run idempotent. update_only is
    # REFRESHABLE_ATTRIBUTES, not "everything" -- an existing row's curator
    # fields (and translations) must survive a re-seed untouched. Regression-
    # tested: see the "update half" example in spec/services/family_seeder_spec.rb.
    Family.importing do
      attributes.each_slice(500) do |slice|
        Family.upsert_all(slice, unique_by: 'index_families_on_lower_name',
                                 update_only: REFRESHABLE_ATTRIBUTES)
      end
    end
  end
end
