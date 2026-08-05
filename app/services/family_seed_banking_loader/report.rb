# frozen_string_literal: true

class FamilySeedBankingLoader
  # The printable dry-run/live-run report produced by
  # FamilySeedBankingLoader#run. Split into its own file to keep
  # FamilySeedBankingLoader itself under Metrics/ClassLength, mirroring
  # FamilyReconciler::Report.
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
end
