# frozen_string_literal: true

require 'net/http'
require 'json'

# Resolves a cleaned family-name candidate to a Family row.
#
# The local list is authoritative, because it came from the Catalogue of Life,
# which gets family merges right where GBIF does not: COL treats Tiliaceae,
# Durionaceae, Asclepiadaceae, Chenopodiaceae and Bombacaceae as synonyms of
# their modern families, and routes Guttiferae to Clusiaceae as the botanical
# code requires, where GBIF sends it to Hypericaceae.
#
# COL has no fuzzy matching at all, so genuine typos need GBIF. GBIF is asked
# only how a name should be SPELLED; the corrected spelling is then resolved
# against the local COL-sourced list, so COL always decides which family a
# plant belongs to.
class FamilyResolver
  GBIF_MATCH = 'https://api.gbif.org/v1/species/match'
  IN_SCOPE_KINGDOMS = %w[Plantae Fungi Chromista].freeze

  def resolve(name)
    local = find_local(name)
    return { family: local, via: :local, confidence: nil } if local

    corrected = gbif_spelling(name)
    if corrected
      family = find_local(corrected[:spelling])
      if family
        return { family: family, via: :gbif_corrected,
                 confidence: corrected[:confidence], spelling: corrected[:spelling] }
      end
    end

    { family: nil, via: :unresolved, confidence: nil }
  end

  private

  def find_local(name)
    Family.accepted.find_by('lower(name) = ?', name.to_s.downcase)
  end

  # Guard on kingdom and rank, not confidence. A threshold cannot separate the
  # good from the bad here: the correct recovery of Curcurbitaceae comes back at
  # confidence 5, while the garbage match for Fabacaea comes back at 0.
  def acceptable_gbif_match?(payload)
    return false if payload.nil?
    return false if payload['family'].blank?
    return false unless IN_SCOPE_KINGDOMS.include?(payload['kingdom'])

    !['NONE', nil].include?(payload['matchType'])
  end

  def gbif_spelling(name)
    payload = gbif_match(name)
    return nil if payload.nil?

    return { spelling: payload['family'], confidence: payload['confidence'] } if acceptable_gbif_match?(payload)

    alternative = (payload['alternatives'] || []).find { |alt| acceptable_gbif_match?(alt) }
    return nil unless alternative

    { spelling: alternative['family'], confidence: alternative['confidence'] }
  end

  def gbif_match(name)
    uri = URI(GBIF_MATCH)
    uri.query = URI.encode_www_form(name: name, rank: 'FAMILY', verbose: 'true')
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError
    nil
  end
end
