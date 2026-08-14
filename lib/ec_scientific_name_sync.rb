# frozen_string_literal: true

# Promotes ECHOcommunity's scientific names into the API during the plant-data
# ownership migration.
#
# Under D-033 a plant's displayed title on ECHOcommunity becomes its scientific
# name, and under D-034 ECHOcommunity's value wins where the two systems
# disagree - its plant data has been curated since the 2020 export and the
# API's has not. Moving the name here first means the title ECHOcommunity shows
# still comes from the API, so the API stays the system of record rather than
# ECHOcommunity quietly keeping ownership of the field.
#
# The incoming values are cleaned upstream, in the migration workspace, where
# the rules and their reasoning live together. This class applies that decision
# and deliberately does no rewriting of its own.
#
# Two guards:
#
#   * A blank incoming value is never written. The scientific name is about to
#     become a page title, so erasing one would leave a plant untitled.
#   * Only `scientific_name` moves. Everything else on the Plant - visibility,
#     ownership, translations, common names - is left alone.
class EcScientificNameSync
  Result = Struct.new(:changed, :unchanged, :blank_skipped, :missing_plants,
                      :failed, :changes, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def sync(plants)
    result = Result.new(changed: 0, unchanged: 0, blank_skipped: 0,
                        missing_plants: 0, failed: 0, changes: [], errors: [])
    plants.each { |uuid, name| sync_plant(uuid, name, result) }
    result
  end

  private

  def sync_plant(uuid, incoming, result)
    return result.blank_skipped += 1 if incoming.blank?

    plant = Plant.unscoped.find_by(id: uuid)
    return result.missing_plants += 1 if plant.nil?
    return result.unchanged += 1 if plant.scientific_name == incoming

    apply_name(plant, incoming, result)
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  def apply_name(plant, incoming, result)
    result.changed += 1
    result.changes << "#{plant.scientific_name.inspect} -> #{incoming.inspect}"
    return unless @apply

    plant.scientific_name = incoming
    plant.save!
  end
end
