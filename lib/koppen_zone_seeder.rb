# frozen_string_literal: true

require Rails.root.join('lib/koppen_zone_data')

# Seeds the Köppen-Geiger climate zones (D-017). The list itself, and the
# reasoning behind which rows exist, is in lib/koppen_zone_data.rb.
#
# Idempotent: re-seeding updates the structural columns and leaves any English
# name a curator has since edited alone, since the name lives in the editable
# translated layer.
class KoppenZoneSeeder
  include KoppenZoneData

  ALL = KoppenZoneData::ALL
  SOURCE = KoppenZoneData::SOURCE
  VERSION = KoppenZoneData::VERSION
  SNAPSHOT = KoppenZoneData::SNAPSHOT

  Result = Struct.new(:created, :updated, :unchanged, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def seed
    result = Result.new(created: 0, updated: 0, unchanged: 0)
    KoppenZone.importing do
      # Two passes: every parent must exist before a child can reference it.
      ALL.each { |code, _p, auth, name, level| upsert(code, level, auth, name, result) }
      link_parents if @apply
    end
    result
  end

  private

  def upsert(code, level, authoritative, name, result)
    zone = KoppenZone.find_by(code: code)
    attrs = structural_attrs(code, level, authoritative)
    return create_zone(code, attrs, name, result) if zone.nil?

    if attrs.any? { |k, v| zone.public_send(k) != v }
      result.updated += 1
      zone.update!(attrs) if @apply
    else
      result.unchanged += 1
    end
  end

  # Everything the classification fixes. The name is deliberately absent: it
  # lives in the editable translated layer, so a re-seed must not overwrite a
  # curator's wording.
  def structural_attrs(code, level, authoritative)
    { level: level, authoritative: authoritative,
      classification_source: SOURCE, classification_version: VERSION,
      snapshot_date: SNAPSHOT, position: ALL.index { |r| r[0] == code } }
  end

  def create_zone(code, attrs, name, result)
    result.created += 1
    return unless @apply

    zone = KoppenZone.new(attrs.merge(code: code))
    Mobility.with_locale(:en) { zone.name = name }
    zone.save!
  end

  def link_parents
    by_code = KoppenZone.all.index_by(&:code)
    ALL.each do |code, parent_code, _auth, _name, _level|
      next if parent_code.nil?

      zone = by_code[code] or next
      parent = by_code[parent_code] or next
      zone.update!(parent_id: parent.id) unless zone.parent_id == parent.id
    end
  end
end
