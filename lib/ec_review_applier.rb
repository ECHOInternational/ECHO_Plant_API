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
#   * **Flag rulings are checked against what the reviewer saw** (D-056): a
#     boolean has only two states, so "already holds the ruled value" cannot
#     tell "untouched since the review" from "flipped twice". A flag ruling may
#     carry 'was'; if the database no longer holds it, the row is refused.
class EcReviewApplier
  # Range rulings carry 'lo'/'hi' instead of 'value'/'locale'; a nil 'hi' is an
  # open upper bound ("1500 m and up"), which EcRangeParser cannot express.
  RANGE_ATTRIBUTES = %w[
    optimal_temperature_range ph_range optimal_rainfall_range optimal_altitude_range
  ].freeze

  # Flag rulings carry 'flag' (true/false) instead of 'value'/'locale', and
  # optionally 'was' — the API value the review page showed the reviewer.
  FLAG_ATTRIBUTES = %w[
    can_be_used_for_fodder has_edible_green_leaves
    has_edible_immature_fruit has_edible_mature_fruit
  ].freeze

  Result = Struct.new(:applied, :already_applied, :blank_refused, :not_governed,
                      :range_occupied, :stale_refused, :missing_plants, :failed,
                      :changes, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  # @param rulings [Array<Hash>] each {'plant_id','locale','attribute','value'}
  def apply(rulings)
    result = Result.new(applied: 0, already_applied: 0, blank_refused: 0,
                        not_governed: 0, range_occupied: 0, stale_refused: 0,
                        missing_plants: 0, failed: 0, changes: [], errors: [])
    rulings.each { |ruling| apply_ruling(ruling, result) }
    result
  end

  private

  def apply_ruling(ruling, result)
    refusal = refuse(ruling)
    return result[refusal] += 1 if refusal

    case ruling['attribute'].to_s
    when *RANGE_ATTRIBUTES then write_range(ruling, result)
    when *FLAG_ATTRIBUTES then write_flag(ruling, result)
    else write(ruling, result)
    end
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{ruling['plant_id']}: #{e.class}: #{e.message}"
  end

  def refuse(ruling)
    attr = ruling['attribute'].to_s
    return :not_governed unless governed?(attr)
    return :blank_refused if blank_ruling?(attr, ruling)

    nil
  end

  def governed?(attr)
    RANGE_ATTRIBUTES.include?(attr) || FLAG_ATTRIBUTES.include?(attr) ||
      EcDataSource::PLANT_ATTRIBUTES.include?(attr)
  end

  # Each kind carries its value under its own key; none of them may blank a
  # field, so a missing or wrong-shaped value is a refusal, not a nil write.
  def blank_ruling?(attr, ruling)
    return ruling['lo'].nil? if RANGE_ATTRIBUTES.include?(attr)
    return [true, false].exclude?(ruling['flag']) if FLAG_ATTRIBUTES.include?(attr)

    ruling['value'].to_s.strip.empty?
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

  # An overwrite by design: the reviewer saw both values side by side and chose
  # one. The 'was' guard is what keeps that from becoming a blind write — see
  # the class comment.
  def write_flag(ruling, result)
    plant = Plant.unscoped.find_by(id: ruling['plant_id'])
    return result.missing_plants += 1 if plant.nil?

    current = plant.public_send(ruling['attribute'])
    return result.stale_refused += 1 if ruling.key?('was') && current != ruling['was']
    return result.already_applied += 1 if current == ruling['flag']

    set_flag(plant, ruling, current, result)
  end

  def set_flag(plant, ruling, current, result)
    attr, flag = ruling.values_at('attribute', 'flag')
    result.applied += 1
    result.changes << "#{plant.id} #{attr}: #{current.inspect} -> #{flag.inspect}"
    return unless @apply

    plant.public_send("#{attr}=", flag)
    plant.save!
  end
end
