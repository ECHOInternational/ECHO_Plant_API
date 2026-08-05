# frozen_string_literal: true

class FamilyReconciler
  # The printable dry-run/live-run report produced by FamilyReconciler#run.
  # Split into its own file to keep FamilyReconciler itself under
  # Metrics/ClassLength; nothing here touches the database, it only formats
  # the classification already decided by FamilyReconciler#classify.
  Report = Struct.new(:dry_run, :applied, :review, :blank, :plant_count, keyword_init: true) do
    def to_s
      [header, counts, review_detail, distribution, footer].join("\n")
    end

    private

    def header
      bar = '=' * 68
      "#{bar}\nRECONCILIATION REPORT - #{plant_count} plants\n#{bar}"
    end

    def counts
      [
        format('  %<label>-46s %<count>5d', label: 'Would be applied', count: applied.size),
        format('  %<label>-46s %<count>5d', label: 'Requires a human decision', count: review.size),
        format('  %<label>-46s %<count>5d', label: 'Blank family_names, left null', count: blank.size)
      ].join("\n")
    end

    def review_detail
      lines = ["\nEVERY RECORD REQUIRING A HUMAN DECISION"]
      review.each { |row| lines.concat(review_row_lines(row)) }
      lines.join("\n")
    end

    def review_row_lines(row)
      lines = ['']
      lines << "  plant : #{row[:plant].scientific_name}"
      lines << "  raw   : #{row[:plant].family_names.inspect}"
      lines << "  reason: #{row[:reason]}"
      row[:results].each do |r|
        lines << "          -> #{r[:family]&.name || '(no match)'} via=#{r[:via]} conf=#{r[:confidence]}"
      end
      lines
    end

    def distribution
      lines = ["\nRESULTING FAMILY DISTRIBUTION"]
      applied.group_by { |a| a[:family].name }.sort_by { |_, v| -v.size }.each do |name, rows|
        lines << format('  %<count>4d  %<name>s', count: rows.size, name: name)
      end
      lines.join("\n")
    end

    def footer
      return "\nDRY RUN. Nothing was written. Re-run with DRY_RUN=0 to apply." if dry_run

      "\nApplied #{applied.size} family links. #{review.size} still need review."
    end
  end
end
