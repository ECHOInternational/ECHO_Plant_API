# frozen_string_literal: true

# Reconciles the legacy free-text plants.family_names column onto the
# families table.
#
# Extracted out of lib/tasks/families.rake (which is now a thin CLI wrapper)
# so the classification decision tree -- blank, unresolved-or-conflicting,
# low-confidence, or applied -- has an automated regression test, mirroring
# FamilySeeder. This is the logic that decides which plants get auto-linked
# versus sent to human review, so it is covered directly rather than only by
# inspection.
class FamilyReconciler
  def initialize(resolver: FamilyResolver.new, min_confidence: 80, dry_run: true, scope: Plant.all)
    @resolver = resolver
    @min_confidence = min_confidence
    @dry_run = dry_run
    @scope = scope
  end

  def run
    applied, review, blank = classify_all

    write!(applied) unless @dry_run

    Report.new(dry_run: @dry_run, applied: applied, review: review, blank: blank, plant_count: @scope.count)
  end

  private

  def classify_all
    applied = []
    review = []
    blank = []
    cache = {}

    @scope.find_each do |plant|
      row = classify(plant, cache)
      case row[:status]
      when :blank then blank << row
      when :review then review << row
      else applied << row
      end
    end

    [applied, review, blank]
  end

  def classify(plant, cache)
    parsed = FamilyNameNormalizer.call(plant.family_names)
    return { plant: plant, status: :blank } if parsed[:kind] == :blank

    row_for(plant, resolve_candidates(parsed[:candidates], cache))
  end

  def resolve_candidates(candidates, cache)
    candidates.map { |c| cache[c] ||= @resolver.resolve(c) }
  end

  def row_for(plant, results)
    return conflict_row(plant, results) if conflicting?(results)
    return low_confidence_row(plant, results, family_for(results)) if low_confidence?(results)

    { plant: plant, status: :applied, family: family_for(results), results: results }
  end

  def conflicting?(results)
    families = results.filter_map { |r| r[:family] }.uniq
    families.size != 1 || results.any? { |r| r[:family].nil? }
  end

  def low_confidence?(results)
    confidences = results.filter_map { |r| r[:confidence] }
    confidences.any? && confidences.min < @min_confidence
  end

  def family_for(results)
    results.filter_map { |r| r[:family] }.uniq.first
  end

  def conflict_row(plant, results)
    { plant: plant, status: :review, results: results, reason: :unresolved_or_conflicting }
  end

  def low_confidence_row(plant, results, family)
    { plant: plant, status: :review, results: results, reason: :low_confidence, family: family }
  end

  def write!(applied)
    applied.each { |row| row[:plant].update_columns(family_id: row[:family].id) }
  end
end
