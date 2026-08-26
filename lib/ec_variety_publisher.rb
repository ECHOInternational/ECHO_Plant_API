# frozen_string_literal: true

# Publishes API varieties that ECHOcommunity already publishes but the API
# still keeps organization-only.
#
# Decision of 2026-08-26. After the variety import, 27 records ECHOcommunity
# publishes were still absent from the API's public set. 26 of them were not
# missing at all - they exist, are ECHO-owned, and sit at
# publication_state=draft / access_level=organization, so the D-006 display
# rule hides them. All 26 were created on 2020-11-03 and have never been
# edited since (created_at = updated_at), which is what makes this safe to do
# in bulk: organization-only is a leftover default from the original import
# rather than an editorial decision anyone took about these cultivars.
#
# Sixteen of the 26 hang off a parent plant that is itself draft here. That is
# not a state this class invents - those parents are draft in ECHOcommunity
# too, where the variety pages are live regardless, because a variety's status
# is independent of its parent's. Publishing mirrors ECHOcommunity (D-002,
# D-034) rather than introducing a new inconsistency.
#
# Four guards, and the third is the one that matters:
#
#   * A variety that is not in the API is reported, never created. Creating is
#     the importer's job and it has its own guards.
#   * A variety that is not ECHO-owned is left alone. D-006 scopes the public
#     view by owning organization, so publishing someone else's record would
#     put it on echocommunity.org.
#   * **A soft-deleted variety is never resurrected.** The 27th record,
#     Earleaf Acacia, was deleted in plant-admin on 2026-08-25 while
#     ECHOcommunity still publishes it. Which side is right is a human call,
#     and quietly un-deleting it here would answer that question by accident.
#   * A variety that is already public is counted and skipped, so the task is
#     idempotent and safe to re-run.
class EcVarietyPublisher
  Result = Struct.new(:published, :already_public, :deleted, :not_echo_owned,
                      :missing, :failed, :errors, :changes, keyword_init: true)

  def initialize(organization:, apply: false)
    @organization = organization
    @apply = apply
  end

  def publish(uuids)
    result = Result.new(published: 0, already_public: 0, deleted: 0,
                        not_echo_owned: 0, missing: 0, failed: 0,
                        errors: [], changes: [])
    uuids.each { |uuid| publish_one(uuid, result) }
    result
  end

  private

  def publish_one(uuid, result)
    variety = Variety.unscoped.find_by(id: uuid)
    reason = skip_reason(variety)
    if reason
      result.public_send("#{reason}=", result.public_send(reason) + 1)
      return
    end

    apply_to(variety, result)
  rescue StandardError => e
    result.published -= 1 if result.published.positive?
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  def skip_reason(variety)
    return :missing if variety.nil?
    return :deleted if variety.deleted_at.present?
    return :not_echo_owned unless variety.owner_organization_id == @organization.id
    return :already_public if variety.access_level == 'public'

    nil
  end

  # Sets the trio, not the legacy integer, so the OrganizedResource dual-write
  # takes its new-API path and derives visibility from what we set here.
  # Saved through the model so PaperTrail records who changed it and why.
  def apply_to(variety, result)
    result.published += 1
    result.changes << "#{variety.id} #{name_of(variety)}"
    return unless @apply

    variety.publication_state = 'published'
    variety.access_level = 'public'
    variety.save!
  end

  def name_of(variety)
    (variety.translations['en'] || {})['name'].presence || '(unnamed in en)'
  end
end
