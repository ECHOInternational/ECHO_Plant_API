# frozen_string_literal: true

class FamilyRefresh
  # Computes the diff hash FamilyRefresh#diff returns. Split into its own
  # file, mirroring FamilyRefresh::Report, to keep FamilyRefresh itself under
  # Metrics/ClassLength: this class is the "what changed" half; the apply_*
  # methods staying on FamilyRefresh are the "what to do about it" half, and
  # nothing here writes to the database.
  class DiffBuilder
    def initialize(upstream, upstream_by_name, client)
      @upstream = upstream
      @upstream_by_name = upstream_by_name
      @client = client
    end

    def call
      local = Family.accepted.to_a
      local_names = local.to_set { |f| f.name.downcase }
      added, col_id_conflicts, added_names = partition_upstream(local_names)
      vanished = local.reject { |f| @upstream_by_name.key?(f.name.downcase) }
      classification = classify_vanished(vanished, added_names, local_names)

      finalize(local.size, added, col_id_conflicts, vanished, classification)
    end

    private

    # A rename target must never be inserted as a fresh row (see
    # #exclude_rename_targets), and a resurrected name must never be upserted
    # as if it were plant-less and new (see #split_resurrected). Both are
    # handled by their own FamilyRefresh#apply_* method, never by
    # #apply_additions!.
    def finalize(local_count, added, col_id_conflicts, vanished, classification)
      fresh, resurrected = split_resurrected(exclude_rename_targets(added, classification[:renamed_candidates]))
      additions = { added: fresh, resurrected: resurrected, col_id_conflicts: col_id_conflicts }
      build_diff(local_count, additions, vanished, classification)
    end

    def build_diff(local_count, additions, vanished, classification)
      {
        added: additions[:added],
        resurrected: additions[:resurrected],
        col_id_conflicts: additions[:col_id_conflicts],
        vanished: vanished,
        affected_plant_counts: vanished.to_h { |f| [f.name, f.plants.count] },
        unchanged: local_count - vanished.size
      }.merge(classification)
    end

    def partition_upstream(local_names)
      added, col_id_conflicts = added_candidates(local_names).partition { |row| col_id_available?(row) }
      [added, col_id_conflicts, added.to_set { |r| r[:name].downcase }]
    end

    def added_candidates(local_names)
      @upstream.reject { |r| local_names.include?(r[:name].downcase) }
    end

    # #classify_synonym puts a vanished family in :renamed_candidates only
    # because its target name showed up in THIS upstream batch with no local
    # match -- which is exactly what added_names is built from. Left
    # unfiltered, +added+ would always contain a rename's target, so applying
    # additions would insert a fresh, plant-less row under the new name before
    # the rename runs, and FamilyRefresh#apply_rename would then collide with
    # it on index_families_on_lower_name instead of updating the original row
    # in place. Excluding the target here is what keeps a rename appliable
    # after additions have already been applied.
    def exclude_rename_targets(added, renamed_candidates)
      targets = renamed_candidates.to_set { |c| c[:target_name].downcase }
      added.reject { |row| targets.include?(row[:name].downcase) }
    end

    # Catalogue of Life publishes resurrected.tsv per release: a name we once
    # merged away (status: superseded, superseded_by pointing at the family
    # it was folded into) can be re-accepted later. Its name is absent from
    # Family.accepted, so #added_candidates treats it as brand new -- but
    # upserting it as a plain addition would flip status back to accepted
    # while leaving superseded_by_id pointing at the other family, a row that
    # is simultaneously accepted and claims to be superseded. Splitting it out
    # here means FamilyRefresh#apply_additions! never upserts onto an existing
    # row at all (short of the col_id hazard, already handled separately), so
    # that dangling pointer cannot happen; #apply_resurrection! is the only
    # path that clears it.
    def split_resurrected(rows)
      fresh, resurrected_rows = rows.partition { |row| superseded_by_name[row[:name].downcase].nil? }
      [fresh, resurrected_rows.map { |row| { row: row, family: superseded_by_name[row[:name].downcase] } }]
    end

    def superseded_by_name
      @superseded_by_name ||= Family.superseded.to_a.index_by { |f| f.name.downcase }
    end

    # Splits the single "gone" bucket into the four cases the design doc
    # distinguishes (docs/superpowers/specs/2026-08-05-botanical-families-design.md
    # section 9), using one CatalogueOfLife#synonym_lookup request per vanished
    # name -- never per family, since a real COL monthly release moves the
    # family count by single digits. Detection only: nothing here writes
    # anything. A human reads the report and chooses FamilyRefresh#apply_rename
    # or #apply_merge; #call never picks for them.
    #
    # Real split detection (design doc: "new accepted families appeared under
    # the SAME PARENT") would need each vanished name's higher classification
    # (its order) compared against every added row's, which neither our
    # schema nor CatalogueOfLife#all_families carries, and fetching it per
    # added row would violate the one-request-per-VANISHED-name budget this
    # method is built to respect. Absent that, a COL "ambiguous synonym" --
    # COL's own status for a name with no single successor -- is used as the
    # best available proxy for a split; see the class comment above
    # +classify_family+ and the fix report for the full reasoning.
    def classify_vanished(vanished, added_names, local_names)
      buckets = { renamed_candidates: [], merge_candidates: [], split_candidates: [], no_successor: [] }
      vanished.each do |family|
        key, entry = classify_family(family, added_names, local_names)
        buckets[key] << entry
      end
      buckets
    end

    # Never raises: a lookup failure or a status this method does not
    # recognize both fall through to :no_successor, reported and unapplied,
    # exactly like a genuine disappearance -- never guessed at, never
    # silently dropped.
    def classify_family(family, added_names, local_names)
      result = @client.synonym_lookup(family.name)
      case result[:status]
      when :synonym then classify_synonym(family, result[:accepted_name], added_names, local_names)
      when :ambiguous_synonym then [:split_candidates, candidate(family)]
      else [:no_successor, candidate(family)]
      end
    rescue StandardError
      [:no_successor, candidate(family)]
    end

    def classify_synonym(family, target_name, added_names, local_names)
      return [:no_successor, candidate(family)] if target_name.blank?
      return [:renamed_candidates, candidate(family, target_name)] if added_names.include?(target_name.downcase)
      return [:merge_candidates, candidate(family, target_name)] if local_names.include?(target_name.downcase)

      # The target is neither newly added nor already held under that exact
      # name -- most likely an authorship/formatting difference in the name
      # string COL returned. Report it, do not guess which bucket it belongs
      # in.
      [:no_successor, candidate(family, target_name)]
    end

    def candidate(family, target_name = nil)
      { family: family, plant_count: family.plants.count, target_name: target_name }
    end

    # Guards the col_id hazard carried over from the seeder: col_id has its
    # own unique partial index (index_families_on_col_id), separate from the
    # lower(name) index this diff matches on. A COL release can recycle an id
    # onto a different family than the one that held it locally, or two new
    # rows in the same release can arrive sharing one id; either would abort
    # the whole Family.importing transaction with a hard uniqueness violation
    # mid-batch. Filtering here, before any write is attempted, turns that
    # crash into a reviewable list (diff[:col_id_conflicts]) instead. Mutates
    # the memoized set so a duplicate col_id among the added rows themselves
    # is caught too, not just a collision with an existing row.
    def col_id_available?(row)
      return true if row[:col_id].blank?
      return false if seen_col_ids.include?(row[:col_id])

      seen_col_ids << row[:col_id]
      true
    end

    def seen_col_ids
      @seen_col_ids ||= Family.where.not(col_id: nil).pluck(:col_id).to_set
    end
  end
end
