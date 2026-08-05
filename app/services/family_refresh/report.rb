# frozen_string_literal: true

class FamilyRefresh
  # The printable diff summary produced by FamilyRefresh#diff for the
  # families:refresh rake task. Split into its own file, mirroring
  # FamilyReconciler::Report and FamilySeedBankingLoader::Report: this keeps
  # the rake task thin and FamilyRefresh itself under Metrics/ClassLength.
  # Nothing here touches the database, it only formats a diff hash that was
  # already computed.
  #
  # The four bucket sections below (rename/merge/split/no-successor) are
  # candidates from one automated name lookup per vanished name, not
  # taxonomic facts -- see FamilyRefresh#classify_vanished. This is the
  # output an operator actually reads before typing 'yes', so the legend
  # saying so lives here, not only in a report file nobody opens at 2am.
  class Report
    # [title, diff key, verb] for each vanished-family bucket, in the order
    # they print. Kept as one table instead of four near-identical methods.
    BUCKETS = [
      ['RENAME CANDIDATES (same taxon, new label)', :renamed_candidates, 'apply_rename'],
      ['MERGE CANDIDATES (now a synonym of a family we already hold)', :merge_candidates, 'apply_merge'],
      ['SPLIT CANDIDATES (COL names no single successor)', :split_candidates, nil],
      ['NO SUCCESSOR FOUND (gone upstream, nothing plausible)', :no_successor, nil]
    ].freeze

    def initialize(diff)
      @diff = diff
    end

    def to_s
      ([header, counts, legend] + bucket_sections + [resurrected_detail, col_id_conflict_detail, footer])
        .compact.join("\n")
    end

    private

    attr_reader :diff

    def header
      bar = '=' * 68
      "#{bar}\nFAMILY REFRESH DIFF\n#{bar}"
    end

    def counts
      [
        count_line('unchanged', diff[:unchanged]),
        count_line('new upstream (would be added)', diff[:added].size),
        count_line('resurrected (superseded, now accepted again)', diff[:resurrected].size),
        count_line('gone upstream, total (see buckets below)', diff[:vanished].size)
      ].join("\n")
    end

    def count_line(label, count)
      format('  %<label>-40s %<count>5d', label: label, count: count)
    end

    def legend
      "\nEach bucket below comes from one Catalogue of Life name lookup per vanished " \
        'family. It is a candidate, not a fact: verify against COL directly before ' \
        'running apply_rename or apply_merge. Nothing has been changed by this report.'
    end

    def bucket_sections
      BUCKETS.map { |title, key, verb| bucket_detail(title, diff[key], verb) }
    end

    def bucket_detail(title, entries, verb)
      return nil if entries.empty?

      lines = ["\n#{title}"]
      lines << "Human decision required. Confirmed by re-running with #{verb} on each." if verb
      entries.each { |entry| lines << bucket_line(entry) }
      lines.join("\n")
    end

    def bucket_line(entry)
      arrow = entry[:target_name] ? " -> #{entry[:target_name]}" : ''
      "  #{entry[:family].name}#{arrow} (#{entry[:plant_count]} plant(s) reference it)"
    end

    def resurrected_detail
      return nil if diff[:resurrected].empty?

      lines = ["\nRESURRECTED (previously superseded, Catalogue of Life accepts it again)",
               'Not inserted as a new row and not applied by APPLY=1: confirm individually via ' \
               'FamilyRefresh#apply_resurrection!. Plants moved during the original merge stay ' \
               'where they are; this only undoes the status/superseded_by flip.']
      diff[:resurrected].each { |c| lines << "  #{c[:family].name} (was superseded by #{c[:family].superseded_by&.name})" }
      lines.join("\n")
    end

    def col_id_conflict_detail
      return nil if diff[:col_id_conflicts].empty?

      lines = ["\nSKIPPED: col_id ALREADY IN USE, WOULD NOT BE ADDED",
               'Each needs a human decision before it can be added under a different id:']
      diff[:col_id_conflicts].each { |row| lines << "  #{row[:name]} (col_id #{row[:col_id]})" }
      lines.join("\n")
    end

    def footer
      "\nRun with APPLY=1 to add new families. Renames, merges and resurrections are applied " \
        'individually, after review, via FamilyRefresh#apply_rename / #apply_merge / #apply_resurrection!.'
    end
  end
end
