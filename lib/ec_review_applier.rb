# frozen_string_literal: true

require Rails.root.join('lib/ec_data_source')
require Rails.root.join('lib/ec_translation_backfill')

# Applies the human rulings from a D-002 conflict review.
#
# EcTranslationBackfill deliberately refuses to touch a value the API already
# holds — that refusal is what produced the review pile (D-045). This is the
# other half: once a human has ruled that ECHOcommunity's text wins for a
# specific plant/locale/attribute, this writes exactly that value and nothing
# else. It is an overwrite by design, so the payload is a list of explicit
# rulings, never a bulk export — each entry names the decision that authorised
# it.
#
# Guards:
#
#   * **Only the governed narrative attributes** (EcDataSource::PLANT_ATTRIBUTES)
#     and the four public range columns can be written; anything else in the
#     payload is refused and counted.
#   * **A blank incoming value is refused** — a ruling cannot blank a field.
#   * **Idempotent**: where the API already holds the same normalised text the
#     entry is counted and skipped, so a re-run (or an overlapping batch)
#     changes nothing.
#   * **Range rulings are additive only** (D-055): a range the API already
#     holds is refused, because the only reviewed case is "API holds nothing".
#     Overwriting a disputed range would need its own ruling and its own code.
class EcReviewApplier
  # Range rulings carry 'lo'/'hi' instead of 'value'/'locale'; a nil 'hi' is an
  # open upper bound ("1500 m and up"), which EcRangeParser cannot express.
  RANGE_ATTRIBUTES = %w[
    optimal_temperature_range ph_range optimal_rainfall_range optimal_altitude_range
  ].freeze

  Result = Struct.new(:applied, :already_applied, :blank_refused, :not_governed,
                      :range_occupied, :missing_plants, :failed, :changes, :errors,
                      keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  # @param rulings [Array<Hash>] each {'plant_id','locale','attribute','value'}
  def apply(rulings)
    result = Result.new(applied: 0, already_applied: 0, blank_refused: 0,
                        not_governed: 0, range_occupied: 0, missing_plants: 0,
                        failed: 0, changes: [], errors: [])
    rulings.each { |ruling| apply_ruling(ruling, result) }
    result
  end

  private

  def apply_ruling(ruling, result)
    refusal = refuse(ruling)
    return result[refusal] += 1 if refusal

    if RANGE_ATTRIBUTES.include?(ruling['attribute'].to_s)
      write_range(ruling, result)
    else
      write(ruling, result)
    end
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{ruling['plant_id']}: #{e.class}: #{e.message}"
  end

  def refuse(ruling)
    attr = ruling['attribute'].to_s
    if RANGE_ATTRIBUTES.include?(attr)
      return :blank_refused if ruling['lo'].nil?
    elsif EcDataSource::PLANT_ATTRIBUTES.include?(attr)
      return :blank_refused if ruling['value'].to_s.strip.empty?
    else
      return :not_governed
    end
    nil
  end

  # Same honest read as the backfill: the stored container, not the Mobility
  # reader, whose fallbacks would answer with English for a missing locale.
  def write(ruling, result)
    plant = Plant.unscoped.find_by(id: ruling['plant_id'])
    return result.missing_plants += 1 if plant.nil?

    locale, attr, value = ruling.values_at('locale', 'attribute', 'value')
    current = (plant.translations[locale] || {})[attr].to_s
    return result.already_applied += 1 if EcTranslationBackfill.same_text?(current, value)

    overwrite(plant, locale, attr, [current, value], result)
  end

  def overwrite(plant, locale, attr, (current, value), result)
    result.applied += 1
    result.changes << "#{plant.id} [#{locale}] #{attr}: " \
                      "#{current.length} -> #{value.to_s.length} chars"
    return unless @apply

    Mobility.with_locale(locale) { plant.public_send("#{attr}=", value) }
    plant.save!
  end

  # Additive only: the reviewed case is "ECHOcommunity holds a value, the API
  # holds nothing" (D-055). An occupied range is refused, never merged.
  def write_range(ruling, result)
    plant = Plant.unscoped.find_by(id: ruling['plant_id'])
    return result.missing_plants += 1 if plant.nil?
    return result.range_occupied += 1 unless plant.public_send(ruling['attribute']).nil?

    apply_range(plant, ruling, result)
  end

  def apply_range(plant, ruling, result)
    attr, low, high = ruling.values_at('attribute', 'lo', 'hi')
    result.applied += 1
    result.changes << "#{plant.id} #{attr}: nil -> [#{low},#{high || 'open'}]"
    return unless @apply

    plant.public_send("#{attr}=", Range.new(low, high))
    plant.save!
  end
end
