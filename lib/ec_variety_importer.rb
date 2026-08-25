# frozen_string_literal: true

# Creates Plant API varieties from ECHOcommunity's published variety records.
#
# Decision of 2026-08-25: move every name, treating the cultivar list itself as
# the content. 406 of the 501 missing records carry nothing but a name, and a
# named cultivar is information even without prose - "this mango is grown as
# Ruang puang" says something. So the name is what moves.
#
# THE DIRECTION OF RICHNESS IS REVERSED HERE, and that is the thing to hold on
# to. For plants, ECHOcommunity was the better-maintained side. For varieties it
# is the opposite: ECHOcommunity holds a name, a description and planting
# instructions, while an API variety carries 29 translated fields, seven ranges
# and its own taxonomy joins. So this only ever CREATES. A variety that already
# exists in the API is left completely alone - no merge, no field-by-field
# comparison, nothing. Overwriting the richer side with the thinner one is the
# failure mode worth designing against.
#
# Identity is preserved as it was for plants: ECHOcommunity's Resource UUID
# becomes the variety's id. `varieties.id` has a default but is insertable, so
# the two systems keep joining on it.
#
# Three guards:
#
#   * **An existing variety is never touched**, in any state including deleted.
#   * **A variety whose parent plant is not in the API is skipped**, not
#     invented. `plant_id` is NOT NULL and a variety without its plant is
#     meaningless.
#   * **A variety with no name is skipped.** The API validates name presence,
#     and an unnamed cultivar carries nothing.
class EcVarietyImporter
  Result = Struct.new(:created, :already_present, :missing_plants, :no_name,
                      :failed, :errors, :changes, keyword_init: true)

  def initialize(organization:, principal:, owner_email:, apply: false)
    @organization = organization
    @principal = principal
    @owner_email = owner_email
    @apply = apply
  end

  def import(varieties)
    result = Result.new(created: 0, already_present: 0, missing_plants: 0,
                        no_name: 0, failed: 0, errors: [], changes: [])
    varieties.each { |uuid, row| import_one(uuid, row, result) }
    result
  end

  private

  def import_one(uuid, row, result)
    translations = row['translations'] || {}
    reason = skip_reason(uuid, row, translations)
    if reason
      result.public_send("#{reason}=", result.public_send(reason) + 1)
      return
    end

    create_variety(uuid, row, translations, result)
  rescue StandardError => e
    result.created -= 1 if result.created.positive?
    result.failed += 1
    result.errors << "#{uuid}: #{e.class}: #{e.message}"
  end

  # Which guard, if any, stops this row. Named rather than inlined so the three
  # reasons stay legible as a set.
  def skip_reason(uuid, row, translations)
    return :already_present if Variety.unscoped.exists?(id: uuid)
    return :no_name unless translations.values.any? { |f| f['name'].present? }
    return :missing_plants unless Plant.unscoped.exists?(id: row['plant_uuid'])

    nil
  end

  def create_variety(uuid, row, translations, result)
    result.created += 1
    result.changes << "#{uuid} #{translations.dig('en', 'name') || '(unnamed in en)'}"
    return unless @apply

    build(uuid, row, translations).save!
  end

  # Published in ECHOcommunity, so public here. Assigned through the enum so the
  # OrganizedResource dual-write keeps publication_state, access_level and
  # deleted_at consistent rather than leaving the trio half-set.
  def build(uuid, row, translations)
    variety = Variety.new(
      id: uuid, plant_id: row['plant_uuid'],
      owned_by: @owner_email, created_by: @owner_email,
      visibility: :public,
      owner_organization_id: @organization.id,
      source_organization_id: @organization.id,
      created_by_principal_id: @principal.id
    )
    translations.each do |locale, fields|
      Mobility.with_locale(locale) do
        fields.each { |attr, value| variety.public_send("#{attr}=", value) if value.present? }
      end
    end
    variety
  end
end
