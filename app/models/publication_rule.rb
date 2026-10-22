# frozen_string_literal: true

# The single quality setting of the FPI plan (decision Q2, section 3.2): a
# data source's publication_rule decides which of its plants meet the quality
# bar. The wave selector uses sql_condition; Plant#meets_quality_bar? (and
# GraphQL Plant.meetsQualityBar, which ECHOcommunity projects for noindex)
# uses met_by?. spec/models/publication_rule_spec.rb keeps the two in parity.
#
# Version 1:
#
#   {"version": 1, "locale": "en",
#    "text_fields": ["description", "uses", "cultivation"],
#    "min_text_chars": 500, "image_suffices": true}
#
# A plant meets the rule when image_suffices is true and it has at least one
# image (any visibility except deleted), or when the text_fields of locale
# together hold at least min_text_chars characters. Characters, not bytes:
# Ruby String#length and Postgres char_length agree on UTF-8.
class PublicationRule
  include ActiveModel::Validations

  VERSION = 1
  # Translated plain-text plant fields a rule may count. Also the allow-list
  # that makes interpolating the names into sql_condition safe.
  TEXT_FIELDS = %w[
    description info_sheet_description origin uses cultivation habitat notes attribution
    harvesting_and_seed_production planting_instructions
  ].freeze
  DELETED_VISIBILITY = 3
  LOCALE_FORMAT = /\A[a-z]{2,3}(-[A-Za-z]{2,4})?\z/

  attr_reader :rule

  validate :shape

  def initialize(rule)
    @rule = rule.is_a?(Hash) ? rule.deep_stringify_keys : {}
  end

  def locale = rule['locale']
  def text_fields = Array(rule['text_fields'])
  def min_text_chars = rule['min_text_chars']
  def image_suffices? = rule['image_suffices'] == true

  def met_by?(plant)
    return true if image_suffices? && plant.images.where.not(visibility: DELETED_VISIBILITY).exists?

    text_chars(plant) >= min_text_chars
  end

  def text_chars(plant)
    values = (plant.translations || {}).fetch(locale, {}) || {}
    text_fields.sum { |field| values[field].is_a?(String) ? values[field].length : 0 }
  end

  # SQL boolean over the plants table, for where(); the twin of met_by?.
  def sql_condition
    raise ArgumentError, "invalid publication rule: #{errors.full_messages.join(', ')}" unless valid?

    loc = ActiveRecord::Base.connection.quote(locale)
    chars = text_fields.map { |f| "COALESCE(char_length(plants.translations->#{loc}->>'#{f}'), 0)" }.join(' + ')
    text = "(#{chars}) >= #{Integer(min_text_chars)}"
    return "(#{text})" unless image_suffices?

    "(EXISTS (SELECT 1 FROM images WHERE images.imageable_type = 'Plant' AND images.imageable_id = plants.id " \
      "AND images.visibility <> #{DELETED_VISIBILITY}) OR #{text})"
  end

  private

  def shape
    shape_problems.each { |attribute, message| errors.add(attribute, message) }
  end

  def shape_problems
    {
      version: ("must be #{VERSION}" unless rule['version'] == VERSION),
      locale: ('must be a locale code such as en' unless valid_locale?),
      text_fields: ("must be a non-empty subset of #{TEXT_FIELDS.join(', ')}" unless known_text_fields?),
      min_text_chars: ('must be a non-negative integer' unless valid_minimum?),
      image_suffices: ('must be true or false' unless [true, false].include?(rule['image_suffices']))
    }.compact
  end

  def valid_locale?
    locale.is_a?(String) && locale.match?(LOCALE_FORMAT)
  end

  def valid_minimum?
    min_text_chars.is_a?(Integer) && min_text_chars >= 0
  end

  def known_text_fields?
    text_fields.any? && (text_fields - TEXT_FIELDS).empty?
  end
end
