# frozen_string_literal: true

# Applies ECHOcommunity's plant-to-lookup assignments for the three taxonomies
# that were never reconciled: antinutrients, tolerances and growth habits.
#
# These are associations, not attributes, so they are outside SourceSynchronizer's
# scope entirely — it compares scalar and translated fields on a record and knows
# nothing about join tables. This follows the pattern already proven by the
# category and Köppen importers instead.
#
# Lookup rows are matched by UUID, resolved upstream. Unlike plants, the two
# systems do not share ids here: ECHOcommunity's lookups are integer-keyed
# Globalize tables, the API's are UUID-keyed. The crosswalk lives in
# db/seeds/{Antinutrients,Tolerances,GrowthHabits}.json, which carry both ids,
# and tools/export_ec_taxonomies.py resolves it before emitting. Measured
# 2026-08-25: zero drift since 2020 — all 19 antinutrients, 7 tolerances and 5
# growth habits resolve, with no renames.
#
# Additive, like the common-name sync. A link ECHOcommunity no longer lists is
# left in place: removing an assignment is an editorial act, not a migration one.
#
# Two guards:
#
#   * An unknown lookup UUID is reported and aborts the run rather than being
#     created. These are curated taxonomies; a UUID that is not already there
#     means the payload and the database disagree, which is a fault to surface.
#   * A plant not in this database is counted and skipped, so a partial payload
#     cannot fail the run.
class EcTaxonomyImporter
  # One taxonomy's wiring: the join association to write through, and the
  # lookup association whose singular name gives the foreign key.
  Taxonomy = Struct.new(:join_assoc, :lookup_assoc) do
    def foreign_key
      "#{lookup_assoc.to_s.singularize}_id"
    end

    def model
      lookup_assoc.to_s.classify.constantize
    end
  end

  TAXONOMIES = {
    'antinutrients' => Taxonomy.new(:antinutrients_plants, :antinutrients),
    'tolerances' => Taxonomy.new(:tolerances_plants, :tolerances),
    'growth_habits' => Taxonomy.new(:growth_habits_plants, :growth_habits)
  }.freeze

  Result = Struct.new(:linked, :present, :missing_plants, :unknown_lookups,
                      :failed, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  # @param taxonomies [Hash] as emitted by tools/export_ec_taxonomies.py:
  #   { 'tolerances' => { '<plant uuid>' => ['<lookup uuid>', ...] } }
  def import(taxonomies)
    result = Result.new(linked: 0, present: 0, missing_plants: 0,
                        unknown_lookups: [], failed: 0, errors: [])
    taxonomies.each do |name, assignments|
      unless TAXONOMIES.key?(name)
        result.errors << "unknown taxonomy: #{name}"
        result.failed += 1
        next
      end
      import_one(name, assignments || {}, result)
    end
    result.unknown_lookups.uniq!
    result
  end

  private

  def import_one(name, assignments, result)
    taxonomy = TAXONOMIES.fetch(name)
    assignments.each do |plant_uuid, lookup_uuids|
      link_plant(plant_uuid, Array(lookup_uuids), taxonomy, result)
    end
  end

  def link_plant(plant_uuid, lookup_uuids, taxonomy, result)
    plant = Plant.unscoped.find_by(id: plant_uuid)
    return result.missing_plants += 1 if plant.nil?

    link_all(plant, lookup_uuids, taxonomy, result)
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{plant_uuid}: #{e.class}: #{e.message}"
  end

  def link_all(plant, lookup_uuids, taxonomy, result)
    existing = plant.public_send(taxonomy.join_assoc).pluck(taxonomy.foreign_key).to_set
    lookup_uuids.each { |uuid| link_one(plant, uuid, taxonomy, existing, result) }
  end

  def link_one(plant, uuid, taxonomy, existing, result)
    unless taxonomy.model.exists?(id: uuid)
      result.unknown_lookups << "#{taxonomy.lookup_assoc}: #{uuid}"
      return
    end
    return result.present += 1 if existing.include?(uuid)

    result.linked += 1
    return unless @apply

    plant.public_send(taxonomy.join_assoc).create!(taxonomy.foreign_key => uuid)
    existing << uuid
  end
end
