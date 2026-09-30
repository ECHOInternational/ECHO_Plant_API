# frozen_string_literal: true

require Rails.root.join('lib/common_name_corrections/plant_finder')

# Six common names that reached ECHOcommunity's plant pages and should not have.
#
# Where they came from: on 2026-09-04 Steve Snyder answered three questions
# about what the plant pages should show. For common names he chose "take all of
# them from the API", which made the API the single source and pushed seventeen
# names onto the pages. Six of those were flagged at the time as not shippable;
# the answer took them anyway, and they are live. Correcting them at source
# means the next reverse sync carries the fix, rather than a person editing
# pages by hand.
#
# Deliberately NOT part of EcCommonNameSync, which says of itself that "deleting
# a name ECHOcommunity no longer lists is an editorial act, not a migration
# one". This is that editorial act, kept separate so it reads as a decision.
#
# Each correction names its plant by scientific name rather than by UUID, so a
# reviewer can check a line against the page it fixes. PlantFinder resolves that
# name through Catalogue of Life when it does not match directly.
class CommonNameCorrections
  # A bare genus name tells a reader nothing, and the same string arrived on
  # three different species. Removing it leaves those plants their other names;
  # inventing a wattle's common name would be worse than having none.
  DELETIONS = [
    { scientific_name: 'Acacia tumida', name: 'Acacia', language: 'en',
      why: 'the genus name as an English common name, on three different Acacia species' },
    { scientific_name: 'Acacia elachantha', name: 'Acacia', language: 'en',
      why: 'the genus name as an English common name, on three different Acacia species' },
    { scientific_name: 'Acacia torulosa', name: 'Acacia', language: 'en',
      why: 'the genus name as an English common name, on three different Acacia species' },
    { scientific_name: 'Capsicum annuum', name: 'Jalapeno', language: 'en',
      why: 'unaccented duplicate of the accented pepper name on the same plant' }
  ].freeze

  # Spanish names filed as English. A name in the wrong language column is
  # visible to every reader of that language, and invisible to the readers it
  # was written for.
  RETAGS = [
    { scientific_name: 'Abelmoschus caillei', name: 'Quimbombó', language: 'en',
      to_name: 'Quimbombó', to_language: 'es', why: 'Spanish, tagged English' },
    { scientific_name: 'Abelmoschus caillei', name: 'Quimbombótardio', language: 'en',
      to_name: 'Quimbombó tardío', to_language: 'es',
      why: 'Spanish, tagged English, and two words run together' }
  ].freeze

  Result = Struct.new(:deleted, :retagged, :already_gone, :missing_plants,
                      :would_collide, :via_synonym, :lines, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
    @finder = PlantFinder.new
  end

  def run
    result = Result.new(deleted: 0, retagged: 0, already_gone: 0, missing_plants: 0,
                        would_collide: 0, via_synonym: 0, lines: [], errors: [])
    DELETIONS.each { |correction| delete_one(correction, result) }
    RETAGS.each { |correction| retag_one(correction, result) }
    result
  end

  private

  def delete_one(correction, result)
    record = locate(correction, result)
    return if record.nil?

    result.deleted += 1
    result.lines << "DELETE         #{label(correction)} -- #{correction[:why]}"
    record.destroy! if @apply
  rescue StandardError => e
    record_error(correction, e, result)
  end

  def retag_one(correction, result)
    record = locate(correction, result)
    return if record.nil?
    return delete_duplicate(record, correction, result) if target_exists?(record, correction)

    result.retagged += 1
    result.lines << "RETAG          #{label(correction)} -> #{correction[:to_name]} " \
                    "(#{correction[:to_language]}) -- #{correction[:why]}"
    apply_retag(record, correction)
  rescue StandardError => e
    record_error(correction, e, result)
  end

  # `primary` is per language, so an English primary must not travel into
  # Spanish, where it would silently become the name every Spanish reader sees.
  def apply_retag(record, correction)
    return unless @apply

    record.update!(name: correction[:to_name], language: correction[:to_language],
                   primary: false)
  end

  # Retagging onto a name that already exists would leave two identical rows.
  def delete_duplicate(record, correction, result)
    result.would_collide += 1
    result.deleted += 1
    result.lines << "DELETE (dup)   #{label(correction)} -- #{correction[:to_name]} " \
                    "(#{correction[:to_language]}) already exists"
    record.destroy! if @apply
  end

  # The CommonName row a correction refers to, or nil having already recorded
  # why it could not be reached.
  def locate(correction, result)
    found = @finder.call(correction[:scientific_name])
    result.lines << found.line if found.line
    result.via_synonym += 1 if found.via_synonym
    return missing_plant(result) if found.plant.nil?

    find_name(found.plant, correction[:name], correction[:language]) ||
      note_gone(correction, result)
  end

  def missing_plant(result)
    result.missing_plants += 1
    nil
  end

  # Matched case-insensitively on (name, language), as EcCommonNameSync matches,
  # so a recased copy is still found.
  def find_name(plant, name, language)
    plant.common_names.find do |common_name|
      common_name.name.to_s.casecmp?(name.to_s) &&
        common_name.language.to_s.casecmp?(language.to_s)
    end
  end

  def target_exists?(record, correction)
    find_name(record.plant, correction[:to_name], correction[:to_language]).present?
  end

  def note_gone(correction, result)
    result.already_gone += 1
    result.lines << "already gone   #{label(correction)}"
    nil
  end

  def label(correction)
    "#{correction[:scientific_name]}: #{correction[:name]} (#{correction[:language]})"
  end

  def record_error(correction, error, result)
    result.errors << "#{correction[:scientific_name]}: #{error.class}: #{error.message}"
  end
end
