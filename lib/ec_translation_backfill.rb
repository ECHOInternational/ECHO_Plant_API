# frozen_string_literal: true

require Rails.root.join('lib/ec_data_source')

# Backfills narrative text into locales the API does not have.
#
# This is NOT a merge, and deliberately does not go through SourceSynchronizer.
# The substrate carries one baseline per record, and the one we have — the 2020
# export — is English. Measured on production, that also matches where merging
# is actually needed:
#
#   English   1,927 identical    33 only in ECHOcommunity    88 differ
#   Spanish     475 identical  1,229 only in ECHOcommunity    23 differ
#
# Spanish is not a conflict problem. 1,229 of its 1,732 values exist only in
# ECHOcommunity because the 2020 export carried English and French but largely
# skipped Spanish — so for those the API holds nothing to disagree with, and a
# three-way merge against an English baseline would invent conflicts out of
# silence. What is needed is an additive write.
#
# Three guards:
#
#   * **An existing value is never overwritten.** Where the API already holds
#     text, this reports and moves on. That covers the 23 Spanish values that do
#     differ: they are real editorial disagreements and get a human, not a
#     blind write.
#   * **A blank incoming value is never written**, so an empty ECHOcommunity
#     field cannot manufacture an empty translation and, with it, the claim that
#     the record exists in that language.
#   * **Only the governed narrative attributes** are touched, and only in the
#     locales named. Nothing else on the record moves.
class EcTranslationBackfill
  Result = Struct.new(:written, :already_present, :differs, :blank_skipped,
                      :missing_plants, :failed, :conflicts, :errors,
                      keyword_init: true)

  # Markup, entities and whitespace differ constantly between the two systems
  # without the words differing at all - one stores `&nbsp;`, the other a space;
  # one wraps a paragraph the other does not. Comparing raw, the first staging
  # run reported 473 values "different on both sides"; comparing the text, 452
  # of those were identical and only 21 said anything different.
  #
  # A review pile that is 95% markup is worse than a larger one: it trains
  # whoever reads it to skim, and the 21 that matter get skimmed with it. So the
  # comparison is on normalised text. Nothing is rewritten - where the API
  # already holds the same words, it keeps its own copy, punctuation and all.
  def self.same_text?(one, other)
    normalise(one) == normalise(other)
  end

  # Nokogiri rather than a regex and CGI.unescapeHTML, which decodes only the
  # basic five entities and leaves `&nbsp;` sitting there as literal text - so a
  # hand-rolled version still reported markup as disagreement. Parsing the
  # fragment strips the tags and decodes the whole entity set in one pass; the
  # remaining tr flattens the U+00A0 that `&nbsp;` and `&#160;` both become.
  def self.normalise(value)
    # Tags become a SPACE before the fragment is parsed, not nothing. Nokogiri's
    # #text concatenates, so `<p>one</p><p>two</p>` would come out as "onetwo"
    # and compare unequal to the same words wrapped differently - which is
    # exactly the markup-only disagreement this is meant to ignore.
    spaced = value.to_s.gsub(/<[^>]+>/, ' ')
    Nokogiri::HTML.fragment(spaced).text.tr("\u00a0", ' ').gsub(/\s+/, ' ').strip
  end

  def initialize(apply: false, attributes: EcDataSource::PLANT_ATTRIBUTES)
    @apply = apply
    @attributes = attributes
  end

  # @param plants [Hash] uuid => { 'es' => { 'uses' => '...' } }
  def backfill(plants)
    result = Result.new(written: 0, already_present: 0, differs: 0, blank_skipped: 0,
                        missing_plants: 0, failed: 0, conflicts: [], errors: [])
    plants.each { |uuid, by_locale| backfill_plant(uuid, by_locale || {}, result) }
    result
  end

  private

  def backfill_plant(uuid, by_locale, result)
    plant = Plant.unscoped.find_by(id: uuid)
    return result.missing_plants += 1 if plant.nil?

    by_locale.each { |locale, fields| backfill_locale(plant, locale, fields || {}, result) }
    plant.save! if @apply && plant.changed?
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  def backfill_locale(plant, locale, fields, result)
    fields.each do |attr, value|
      next unless @attributes.include?(attr)

      write_field(plant, locale, attr, value, result)
    end
  end

  # Reads the stored container directly rather than through the Mobility reader.
  #
  # The `fallbacks` plugin makes a read of a missing locale return the :en
  # value, so `Mobility.with_locale(:es) { plant.uses }` answers "English text"
  # for a plant with no Spanish at all. Asking the reader whether Spanish
  # already has a value therefore always says yes, every value looks like a
  # conflict, and the backfill silently writes nothing — which is precisely the
  # 1,229 values this exists to move. The container is the only honest answer to
  # "does THIS locale hold text".
  def stored(plant, locale, attr)
    (plant.translations[locale.to_s] || {})[attr].to_s
  end

  def write_field(plant, locale, attr, incoming, result)
    return result.blank_skipped += 1 if incoming.to_s.strip.empty?

    current = stored(plant, locale, attr)
    if current.present?
      return record_existing(plant, { locale: locale, attribute: attr },
                             [current, incoming.to_s], result)
    end

    result.written += 1
    Mobility.with_locale(locale) { plant.public_send("#{attr}=", incoming) } if @apply
  end

  # Text already here is left exactly as it is. Where it also disagrees with
  # ECHOcommunity that is an editorial question, so it is reported rather than
  # resolved.
  def record_existing(plant, where, values, result)
    current, incoming = values
    return result.already_present += 1 if self.class.same_text?(current, incoming)

    result.differs += 1
    result.conflicts << { plant: plant.id, locale: where[:locale],
                          attribute: where[:attribute],
                          api_length: current.length, ec_length: incoming.length }
  end
end
