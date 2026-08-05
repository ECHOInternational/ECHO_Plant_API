# frozen_string_literal: true

# Loads the family-level seed banking guidance supplied on issue #83 onto the
# locked families table.
#
# Extracted out of lib/tasks/families.rake (which is now a thin CLI wrapper),
# mirroring FamilySeeder and FamilyReconciler: the part that actually touches
# the database has an automated regression test.
#
# Only four of the source spreadsheet's six columns are loaded. "Seed Size &
# Handling" and "Dormancy & Germination" are a single value for 303 of 347
# rows ("Variable" and "Varies by species"), so they carry almost no
# information and are left out until they have real content.
#
# The "Count" column from the companion spreadsheet is deliberately NOT
# stored: it is a count of Food Plants International records per family, so
# it would be stale on write and excludes ECHO's own plants. Family.plants
# totalCount serves that need and is always correct.
class FamilySeedBankingLoader
  LONGEVITY = {
    'low' => 'low',
    'low-medium' => 'low_medium',
    'medium' => 'medium',
    'medium-high' => 'medium_high',
    'high' => 'high'
  }.freeze

  Report = Struct.new(
    :dry_run,
    :total,
    :updated,
    :redirected,
    :unmatched,
    keyword_init: true
  ) do
    def to_s
      (summary_lines + redirected_lines + unmatched_lines + closing_lines).join("\n")
    end

    private

    def summary_lines
      ["rows in file        : #{total}", "updated             : #{updated.size}"]
    end

    def redirected_lines
      ['redirected to accepted family:'] + redirected.map { |from, to| "  #{from} -> #{to}" }
    end

    def unmatched_lines
      ["NO TARGET, needs a decision (#{unmatched.size}):"] + unmatched.map { |name| "  #{name}" }
    end

    def closing_lines
      ['', dry_run ? 'DRY RUN. Re-run with DRY_RUN=0 to write.' : 'Done.']
    end
  end

  class << self
    # The source splits one value across an en dash and an ASCII hyphen:
    # 86 rows say "Low-Medium" with U+2013 and 23 say it with '-'. Both must
    # land on the same enum value.
    def normalize_longevity(value)
      return nil if value.blank?

      key = value.to_s.strip.downcase.tr('–—', '--')
      LONGEVITY[key]
    end

    # Checked in order: a hedge like "Recalcitrant/intermediate" must land on
    # 'intermediate', not the first category name it happens to contain, so
    # the table's ORDER carries meaning and is not just a lookup.
    STORAGE_RULES = [
      [->(t) { t.include?('limited data') }, 'unknown'],
      [->(t) { t.include?('intermediate') }, 'intermediate'],
      [->(t) { t.start_with?('mixed') }, 'mixed'],
      [->(t) { t.start_with?('variable') }, 'variable'],
      [->(t) { t.include?('recalcitrant') }, 'recalcitrant'],
      [->(t) { t.include?('orthodox') }, 'orthodox']
    ].freeze

    def normalize_storage(value)
      return nil if value.blank?

      text = value.to_s.downcase
      _matcher, category = STORAGE_RULES.find { |matcher, _category| matcher.call(text) }
      category || 'unknown'
    end

    # "Mostly orthodox (onions, garlic, leeks)" carries editorial detail that
    # the enum cannot hold. Keep it in the notes rather than silently
    # discarding it.
    def qualifier_from(value)
      match = value.to_s.match(/\(([^)]+)\)/)
      match && match[1]
    end
  end

  def initialize(rows:, redirects: {}, dry_run: true)
    @rows = rows
    @redirects = redirects
    @dry_run = dry_run
  end

  def run
    tally = { updated: [], redirected: [], unmatched: [] }

    @rows.each { |row| process_row(row, tally) }

    Report.new(dry_run: @dry_run, total: @rows.size, updated: tally[:updated],
               redirected: tally[:redirected].uniq, unmatched: tally[:unmatched])
  end

  private

  def process_row(row, tally)
    source_name = row['family'].to_s.strip
    target_name = @redirects.fetch(source_name, source_name)
    family = Family.accepted.find_by('lower(name) = ?', target_name.downcase)
    return tally[:unmatched] << source_name if family.nil?

    tally[:redirected] << [source_name, target_name] if target_name != source_name
    apply!(family, row) unless @dry_run
    tally[:updated] << family.name
  end

  def apply!(family, row)
    family.assign_attributes(
      storage_physiology: self.class.normalize_storage(row['storage_physiology']),
      seed_longevity: self.class.normalize_longevity(row['seed_longevity']),
      seed_banking_rank: row['seed_banking_rank'].presence&.to_i
    )
    Mobility.with_locale(:en) { family.seed_banking_notes = notes_for(row).presence }
    family.save!
  end

  def notes_for(row)
    notes = row['seed_banking_notes'].to_s.strip
    qualifier = self.class.qualifier_from(row['storage_physiology'])
    [notes.presence, qualifier && "Storage detail: #{qualifier}"].compact.join('. ')
  end
end
