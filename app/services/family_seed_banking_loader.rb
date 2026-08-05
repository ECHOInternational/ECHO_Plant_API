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
      ['limited data', :include, 'unknown'],
      ['intermediate', :include, 'intermediate'],
      ['mixed', :start_with, 'mixed'],
      ['variable', :start_with, 'variable'],
      ['recalcitrant', :include, 'recalcitrant'],
      ['orthodox', :include, 'orthodox']
    ].freeze

    def normalize_storage(value)
      return nil if value.blank?

      text = value.to_s.downcase
      _keyword, _mode, category = STORAGE_RULES.find { |keyword, mode, _category| storage_match?(text, keyword, mode) }
      category || 'unknown'
    end

    # "Mostly orthodox (onions, garlic, leeks)" carries editorial detail that
    # the enum cannot hold. Keep it in the notes rather than silently
    # discarding it. A row whose category keyword is negated (see
    # +negated?+ below) falls through normalize_storage to 'unknown' with no
    # parenthetical to fall back on; without this, the human meaning behind
    # that fallback -- e.g. "Parasitic plants, no orthodox seeds" -- would be
    # lost entirely rather than merely under-classified. "Limited data" is
    # excluded since its own text already says exactly what the enum says.
    def qualifier_from(value)
      match = value.to_s.match(/\(([^)]+)\)/)
      return match[1] if match

      raw = value.to_s.strip
      return nil if raw.blank? || raw.downcase.include?('limited data')

      raw if normalize_storage(value) == 'unknown'
    end

    private

    # A category keyword's mere presence is not enough: "no orthodox seeds"
    # must NOT match 'orthodox' just because the substring is there. Guards
    # against "no <category>", "not <category>" and "non-<category>".
    def storage_match?(text, keyword, mode)
      return false if negated?(text, keyword)

      mode == :start_with ? text.start_with?(keyword) : text.include?(keyword)
    end

    def negated?(text, keyword)
      text.match?(/\b(?:no|not|non-)\s*#{Regexp.escape(keyword)}/)
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
    Mobility.with_locale(:en) { family.seed_banking_notes = merged_notes(family, row) }
    family.save!
  end

  # A redirect (a COL-synonym family's guidance landing on its accepted
  # family, e.g. Chenopodiaceae onto Amaranthaceae) can arrive at a family
  # that already has notes from its OWN row in this same file. Overwriting
  # would silently discard whichever row is processed first, which is
  # exactly the editorial content the design document says must never be
  # silently discarded. Appending instead keeps both.
  #
  # This must be idempotent, not just non-clobbering: the loader can be
  # re-run against a database that already has last run's output on it (a
  # partial-failure retry, a CSV correction, a staging rehearsal replayed
  # against the same seed). Without a "would this already be there" check,
  # every re-run appends both halves again --
  # "Highly suitable. Merged family. Highly suitable. Merged family. ..." --
  # onto a field that is publicly exposed as Family.seedBankingNotes.
  # existing_notes.include?(new_notes) is the check: if this exact
  # contribution is already present, do nothing, rather than tracking
  # per-source state this loader has nowhere to persist.
  #
  # Deliberately appends even when existing_notes came from a curator's own
  # updateFamily edit, not just a previous loader run: there is no column
  # recording where seed_banking_notes came from, so an editor-vs-loader
  # distinction is not available to check, and "discard whatever is already
  # there" would resurrect the exact silent-clobber bug this method exists to
  # avoid, just pointed at curator content instead of CSV content. The
  # design document's rule -- no editorial content is silently discarded --
  # is symmetric: it protects curator prose from this loader exactly as much
  # as it protects one CSV row's notes from another's.
  def merged_notes(family, row)
    new_notes = notes_for(row).presence
    existing_notes = Mobility.with_locale(:en) { family.seed_banking_notes }.presence
    return existing_notes if new_notes.blank?
    return new_notes if existing_notes.blank?
    return existing_notes if existing_notes.include?(new_notes)

    "#{existing_notes}. #{new_notes}"
  end

  def notes_for(row)
    notes = row['seed_banking_notes'].to_s.strip
    qualifier = self.class.qualifier_from(row['storage_physiology'])
    [notes.presence, qualifier && "Storage detail: #{qualifier}"].compact.join('. ')
  end
end
