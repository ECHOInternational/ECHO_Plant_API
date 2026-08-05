# frozen_string_literal: true

# Reduces a free-text plants.family_names value to bare family-name candidates.
#
# Neither COL nor GBIF tolerates trailing text: "Cucurbitaceae - Gourd" matches
# nothing at either source, so the cleaning has to happen before any lookup.
# Every transformation here exists because of a value actually present in
# production data.
module FamilyNameNormalizer
  # Family rank names end in -aceae under the modern code. The eight ICN
  # Art. 18.5 conserved alternatives end in -ae instead and are equally valid.
  FAMILY_TOKEN = /\A[A-Z][a-z]+(?:aceae|ae)\z/
  # Production uses EN DASH exclusively for appended labels; ASCII hyphen and
  # em dash are included for safety.
  TRAILING_SEPARATOR = /\s*[–—-]\s*/
  MULTI_SPACE = /\s{2,}/
  JOINERS = /,|\bOr\b|\bor\b|\band\b/

  module_function

  def call(raw)
    return { candidates: [], kind: :blank } if raw.blank?

    value = squish_control_characters(raw)
    return { candidates: [], kind: :blank } if value.blank?

    families, others = extract_families(split_tokens(value))

    return { candidates: [value], kind: :unrecognised } if families.empty?
    return { candidates: families, kind: :multiple_candidates } if families.size > 1

    kind = others.empty? ? :single : :single_with_trailing_text
    { candidates: families, kind: kind }
  end

  def squish_control_characters(raw)
    raw.to_s.tr("\t\r\n", '   ').strip
  end

  def split_tokens(value)
    value
      .split(/[()]/)
      .flat_map { |part| part.split(JOINERS) }
      .flat_map { |part| part.split(TRAILING_SEPARATOR) }
      .flat_map { |part| part.split(MULTI_SPACE) }
      .map(&:strip)
      .reject(&:blank?)
  end

  # A single space can also separate a family from an appended common name
  # ("Malvaceae Mallow"), so drop to word level only when nothing else matched.
  def extract_families(tokens)
    families, others = tokens.partition { |t| t.match?(FAMILY_TOKEN) }
    families = others.flat_map { |token| token.split.grep(FAMILY_TOKEN) } if families.empty?

    [families.uniq, others]
  end
end
