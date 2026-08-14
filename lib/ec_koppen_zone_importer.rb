# frozen_string_literal: true

# Applies ECHOcommunity's plant-to-climate-zone assignments to the API (D-017).
#
# ECHOcommunity holds 512 of them across 45 zones, entered against the GMCC
# selector since 2017. They are the reason the zone lookup exists: without them
# the selector cannot be migrated.
#
# Zones are matched by `code`, not by id. ECHOcommunity's ids are integers on an
# un-foreign-keyed table whose rows have been deleted before - the parent ids
# are non-contiguous - so the code is the only identifier meaningful across both
# systems.
#
# Additive. A zone ECHOcommunity no longer lists is left in place: removing an
# assignment is an editorial act, not a migration one, and the same reasoning
# the common-name sync follows.
#
# Two guards:
#
#   * **An unknown zone code is reported, never created.** koppen_zones is a
#     locked list; a code that is not in it means the seed and the payload
#     disagree, which is a fault to surface rather than paper over.
#   * **A plant not in this database is counted and skipped**, so a partial
#     payload cannot fail the run.
class EcKoppenZoneImporter
  Result = Struct.new(:linked, :present, :missing_plants, :unknown_zones,
                      :failed, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def import(plants)
    result = Result.new(linked: 0, present: 0, missing_plants: 0,
                        unknown_zones: [], failed: 0, errors: [])
    zones = KoppenZone.all.index_by { |z| z.code.downcase }
    plants.each { |uuid, codes| link(uuid, Array(codes), zones, result) }
    result.unknown_zones.uniq!
    result
  end

  private

  def link(uuid, codes, zones, result)
    plant = Plant.unscoped.find_by(id: uuid)
    return result.missing_plants += 1 if plant.nil?

    existing = plant.koppen_zones_plants.pluck(:koppen_zone_id).to_set
    codes.each { |code| link_one(plant, code, zones, existing, result) }
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  def link_one(plant, code, zones, existing, result)
    zone = zones[code.to_s.downcase]
    if zone.nil?
      result.unknown_zones << code
      return
    end
    return result.present += 1 if existing.include?(zone.id)

    result.linked += 1
    return unless @apply

    KoppenZonesPlant.create!(plant: plant, koppen_zone: zone)
    existing << zone.id
  end
end
