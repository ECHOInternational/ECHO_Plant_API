# frozen_string_literal: true

class FamilyRefresh
  # The printable diff summary produced by FamilyRefresh#diff for the
  # families:refresh rake task. Split into its own file, mirroring
  # FamilyReconciler::Report and FamilySeedBankingLoader::Report: this keeps
  # the rake task thin and FamilyRefresh itself under Metrics/ClassLength.
  # Nothing here touches the database, it only formats a diff hash that was
  # already computed.
  class Report
    def initialize(diff)
      @diff = diff
    end

    def to_s
      [header, counts, vanished_detail, col_id_conflict_detail, footer].compact.join("\n")
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
        count_line('gone upstream (needs a decision)', diff[:vanished].size)
      ].join("\n")
    end

    def count_line(label, count)
      format('  %<label>-40s %<count>5d', label: label, count: count)
    end

    def vanished_detail
      return nil if diff[:vanished].empty?

      lines = ["\nFAMILIES NO LONGER ACCEPTED UPSTREAM",
               'Each needs a human decision. Nothing is repointed automatically.']
      diff[:vanished].each do |family|
        count = diff[:affected_plant_counts][family.name]
        lines << "  #{family.name} (#{count} plant(s) reference it)"
      end
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
      "\nRun with APPLY=1 to add new families. Merges are applied individually, " \
        'after review, via FamilyRefresh#apply_merge.'
    end
  end
end
