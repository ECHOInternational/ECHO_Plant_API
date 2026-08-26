# frozen_string_literal: true

# Un-deletes specific API varieties and returns them to the public set.
#
# This is the deliberate counterpart to EcVarietyPublisher's third guard.
# That class refuses to touch a soft-deleted record, because resurrecting one
# in a bulk sweep would silently overturn a curator's decision. Sometimes
# overturning it is exactly what is wanted - but then it should be an explicit,
# named act, which is why this takes uuids as arguments rather than reading a
# generated file.
#
# First use, 2026-08-26: `Earleaf Acacia`
# (a28b373c-a18a-49ea-90da-8fe73d816fc8). Soft-deleted in plant-admin on
# 2026-08-25 at 14:39 by ssnyder@echonet.org, mid-session while curating
# Acacia auriculiformis, and the deletion looked correct - "Ear Leaf Acacia"
# has been an English common name of that plant since 2020, so the variety
# record was a mis-filed duplicate rather than a cultivar. ECHOcommunity has
# published the variety page since 2018 regardless, and under D-002/D-034
# ECHOcommunity wins. Decision of 2026-08-26: restore it, keep the URL alive,
# and settle the common-name duplication separately.
#
# Restoring clears deleted_at and sets the trio to published/public, because a
# record that is merely un-deleted would fall back to :private and still be
# absent from the public set the guard measures.
#
# Attribution matters more here than elsewhere: this reverses a named person's
# edit, so the PaperTrail version is written with the migration's service
# principal and an origin of 'migration-restore' rather than left blank.
class EcVarietyRestorer
  Result = Struct.new(:restored, :not_deleted, :missing, :failed, :errors,
                      :changes, keyword_init: true)

  def initialize(principal:, apply: false)
    @principal = principal
    @apply = apply
  end

  def restore(uuids)
    result = Result.new(restored: 0, not_deleted: 0, missing: 0, failed: 0,
                        errors: [], changes: [])
    PaperTrail.request(whodunnit: @principal.id,
                       controller_info: { metadata: { origin: 'migration-restore' } }) do
      uuids.each { |uuid| restore_one(uuid, result) }
    end
    result
  end

  private

  def restore_one(uuid, result)
    variety = Variety.unscoped.find_by(id: uuid)
    return count(result, :missing) if variety.nil?
    return count(result, :not_deleted) if variety.deleted_at.nil?

    apply_to(variety, result)
  rescue StandardError => e
    result.restored -= 1 if result.restored.positive?
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  def count(result, field)
    result.public_send("#{field}=", result.public_send(field) + 1)
  end

  def apply_to(variety, result)
    result.restored += 1
    result.changes << "#{variety.id} #{name_of(variety)} " \
                      "(deleted #{variety.deleted_at.utc.strftime('%Y-%m-%d %H:%M UTC')})"
    return unless @apply

    variety.deleted_at = nil
    variety.publication_state = 'published'
    variety.access_level = 'public'
    variety.save!
  end

  def name_of(variety)
    (variety.translations['en'] || {})['name'].presence || '(unnamed in en)'
  end
end
