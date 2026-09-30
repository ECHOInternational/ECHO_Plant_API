# frozen_string_literal: true

# Six common names that reached ECHOcommunity's plant pages and should not have.
#
# Where they came from: on 2026-09-04 Steve Snyder answered three questions about
# what the plant pages should show (recorded as decision 63 in the plant-data
# migration workspace). For common names he chose "take all of them from the API",
# which made the API the single source and pushed seventeen names onto the pages.
# Six of those were flagged at the time as not shippable; the answer took them
# anyway, and they are live. This corrects them at source, so the next reverse
# sync carries the correction through rather than a person editing pages.
#
# This is deliberately NOT part of EcCommonNameSync, which says of itself that
# "deleting a name ECHOcommunity no longer lists is an editorial act, not a
# migration one". This class is that editorial act, kept separate and explicit
# so it reads as a decision rather than as drift.
#
# Every correction names the plant by scientific name rather than by UUID: a
# reviewer can check each line against the page it fixes without a lookup.
#
# Finding the plant is not a string equality: a name in this file may be the
# one Catalogue of Life now treats as a synonym while the plant is stored under
# the accepted name, or the reverse. A bare "not found" would report a fix as
# impossible when the plant is sitting there under another name, so the lookup
# falls back to COL rather than giving up. It never guesses: an ambiguous
# synonym (COL's own status for a name with no single successor) is reported,
# not resolved, and a name COL has never heard of stays not found.
class CommonNameCorrections
  require Rails.root.join('lib/catalogue_of_life')

  # A bare genus name tells a reader nothing, and the same string arrived on
  # three different species. Removing it leaves those plants with their other
  # names; inventing a wattle's common name would be worse than having none.
  DELETIONS = [
    { scientific_name: 'Acacia tumida',       name: 'Acacia',   language: 'en',
      why: 'the genus name as an English common name, on three different Acacia species' },
    { scientific_name: 'Acacia elachantha',   name: 'Acacia',   language: 'en',
      why: 'the genus name as an English common name, on three different Acacia species' },
    { scientific_name: 'Acacia torulosa',     name: 'Acacia',   language: 'en',
      why: 'the genus name as an English common name, on three different Acacia species' },
    { scientific_name: 'Capsicum annuum',     name: 'Jalapeno', language: 'en',
      why: 'unaccented duplicate of "Jalapeño Pepper", which is present on the same plant' }
  ].freeze

  # Spanish names filed as English. A name in the wrong language column is
  # visible to every reader of that language, and invisible to the readers it
  # was written for. "Quimbombótardio" also has its two words run together.
  RETAGS = [
    { scientific_name: 'Abelmoschus caillei', name: 'Quimbombó', language: 'en',
      to_name: 'Quimbombó', to_language: 'es',
      why: 'Spanish, tagged English' },
    { scientific_name: 'Abelmoschus caillei', name: 'Quimbombótardio', language: 'en',
      to_name: 'Quimbombó tardío', to_language: 'es',
      why: 'Spanish, tagged English, and two words run together' }
  ].freeze

  Result = Struct.new(:deleted, :retagged, :already_gone, :missing_plants,
                      :would_collide, :resolved_by_col, :lines, :errors, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def run
    result = Result.new(deleted: 0, retagged: 0, already_gone: 0, missing_plants: 0,
                        would_collide: 0, resolved_by_col: 0, lines: [], errors: [])
    DELETIONS.each { |c| delete_one(c, result) }
    RETAGS.each    { |c| retag_one(c, result) }
    result
  end

  private

  # Exact, then case-insensitive, then Catalogue of Life. Each step says how it
  # found the plant, so a reviewer reading the dry run can see when a
  # correction was applied to a plant filed under a different name.
  def plant_for(correction, result)
    name = correction[:scientific_name]
    plant = Plant.unscoped.find_by(scientific_name: name) ||
            Plant.unscoped.where('lower(scientific_name) = ?', name.downcase).first
    return plant if plant

    plant_via_catalogue_of_life(name, result)
  end

  def plant_via_catalogue_of_life(name, result)
    lookup = catalogue_of_life.synonym_lookup(name)
    case lookup[:status]
    when :synonym      then plant_under_accepted_name(name, lookup[:accepted_name], result)
    when :accepted     then report_accepted_but_absent(name, result)
    when :ambiguous_synonym
      # COL has no single successor for this name. Picking one would be a
      # guess about which taxon the page means, so report and stop.
      note_missing(name, result,
                   'Catalogue of Life calls it an ambiguous synonym; it has no single '                    'accepted successor, so no plant was chosen')
    when :error        then note_missing(name, result, 'Catalogue of Life lookup failed')
    else                    note_missing(name, result, 'not found here and unknown to Catalogue of Life')
    end
  end

  def plant_under_accepted_name(name, accepted, result)
    plant = accepted && (Plant.unscoped.find_by(scientific_name: accepted) ||
                         Plant.unscoped.where('lower(scientific_name) = ?', accepted.downcase).first)
    if plant
      result.resolved_by_col += 1
      result.lines << "resolved       #{name} is a synonym; matched the plant filed as #{accepted}"
      return plant
    end

    note_missing(name, result,
                 "Catalogue of Life gives the accepted name as #{accepted || 'unknown'}, "                  'and no plant is filed under either')
  end

  # The name we hold is the accepted one, so the plant is either absent or
  # filed under a synonym. Finding the latter would mean a COL lookup per
  # candidate plant; say what is known instead of doing that for six rows.
  def report_accepted_but_absent(name, result)
    note_missing(name, result,
                 'Catalogue of Life accepts this name, so the plant is either absent or '                  'filed under a synonym of it')
  end

  def note_missing(name, result, reason)
    result.missing_plants += 1
    result.lines << "MISSING PLANT  #{name} — #{reason}"
    nil
  end

  def catalogue_of_life
    @catalogue_of_life ||= CatalogueOfLife.new
  end

  # Matched case-insensitively on (name, language), the same way the sync
  # matches, so a recased copy is still found.
  def find_name(plant, name, language)
    plant.common_names.find do |cn|
      cn.name.to_s.casecmp?(name.to_s) && cn.language.to_s.casecmp?(language.to_s)
    end
  end

  def delete_one(correction, result)
    plant = plant_for(correction, result) or return
    record = find_name(plant, correction[:name], correction[:language])
    if record.nil?
      result.already_gone += 1
      result.lines << "already gone   #{correction[:scientific_name]}: " \
                      "#{correction[:name]} (#{correction[:language]})"
      return
    end

    result.deleted += 1
    result.lines << "DELETE         #{correction[:scientific_name]}: " \
                    "#{correction[:name]} (#{correction[:language]}) — #{correction[:why]}"
    record.destroy! if @apply
  rescue StandardError => e
    result.errors << "#{correction[:scientific_name]}: #{e.class}: #{e.message}"
  end

  def retag_one(correction, result)
    plant = plant_for(correction, result) or return
    record = find_name(plant, correction[:name], correction[:language])
    if record.nil?
      result.already_gone += 1
      result.lines << "already gone   #{correction[:scientific_name]}: " \
                      "#{correction[:name]} (#{correction[:language]})"
      return
    end

    # The target may already exist — a Spanish "Quimbombó" could have arrived
    # separately. Retagging onto it would leave two identical rows, so delete
    # the mistagged one instead and say which happened.
    if find_name(plant, correction[:to_name], correction[:to_language])
      result.would_collide += 1
      result.deleted += 1
      result.lines << "DELETE (dup)   #{correction[:scientific_name]}: " \
                      "#{correction[:name]} (#{correction[:language]}) — " \
                      "#{correction[:to_name]} (#{correction[:to_language]}) already exists"
      record.destroy! if @apply
      return
    end

    result.retagged += 1
    result.lines << "RETAG          #{correction[:scientific_name]}: " \
                    "#{correction[:name]} (#{correction[:language]}) -> " \
                    "#{correction[:to_name]} (#{correction[:to_language]}) — #{correction[:why]}"
    return unless @apply

    # `primary` is per language. A name moving out of English must not carry an
    # English primary flag into Spanish, where it would silently become the name
    # every Spanish reader sees.
    record.update!(name: correction[:to_name], language: correction[:to_language],
                   primary: false)
  rescue StandardError => e
    result.errors << "#{correction[:scientific_name]}: #{e.class}: #{e.message}"
  end
end
