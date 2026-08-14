# frozen_string_literal: true

# Writes curated plant narrative text into the API during the plant-data
# ownership migration.
#
# Built for D-012, which moves species-specific descriptions off ECHOcommunity's
# variety records onto the matching species in the API. The four "Edible
# Australian Acacias" species all carry the same copied group prose, so
# *Acacia torulosa* currently describes *Acacia colei*; this replaces each with
# the paragraph actually written about it. The group-level text it leaves behind
# moves to a Collection (D-011).
#
# Which text belongs to which plant is decided upstream, in the migration
# workspace, where the reasoning lives with the content. This class applies that
# decision and composes nothing of its own.
#
# Three guards:
#
#   * **Only the fields in FIELDS may be written.** A payload naming anything
#     else is a failure, not a silent skip - this task must never become a
#     general-purpose writer for a record the API owns.
#   * **A blank value is never written**, so a description cannot be erased by
#     an incomplete payload.
#   * **Only locales named in the payload are touched.** Other translations on
#     the record are left exactly as they are.
class PlantDescriptionSync
  FIELDS = %w[description info_sheet_description].freeze

  Result = Struct.new(:changed, :unchanged, :blank_skipped, :missing_plants,
                      :failed, :changes, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def sync(plants)
    result = Result.new(changed: 0, unchanged: 0, blank_skipped: 0,
                        missing_plants: 0, failed: 0, changes: [], errors: [])
    plants.each { |uuid, by_locale| sync_plant(uuid, by_locale, result) }
    result
  end

  private

  def sync_plant(uuid, by_locale, result)
    plant = Plant.unscoped.find_by(id: uuid)
    return result.missing_plants += 1 if plant.nil?

    dirty = by_locale.sum { |locale, fields| apply_locale(plant, locale, fields, result) }
    plant.save! if @apply && dirty.positive?
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  def apply_locale(plant, locale, fields, result)
    fields.sum do |field, value|
      unknown = !FIELDS.include?(field)
      raise ArgumentError, "refusing to write #{field.inspect}" if unknown

      write_field(plant, locale, field, value, result)
    end
  end

  def write_field(plant, locale, field, value, result)
    return (result.blank_skipped += 1) && 0 if value.to_s.strip.empty?

    current = Mobility.with_locale(locale) { plant.public_send(field) }
    return (result.unchanged += 1) && 0 if current == value

    result.changed += 1
    result.changes << change_line(plant, locale, field, current, value)
    Mobility.with_locale(locale) { plant.public_send("#{field}=", value) } if @apply
    1
  end

  def change_line(plant, locale, field, current, value)
    "#{plant.scientific_name} [#{locale}] #{field}: " \
      "#{current.to_s.length} -> #{value.length} chars"
  end
end
