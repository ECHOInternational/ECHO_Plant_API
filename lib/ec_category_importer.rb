# frozen_string_literal: true

# Creates missing plant categories and syncs category membership from
# ECHOcommunity during the plant-data ownership migration.
#
# Categories share the UUID convention established in ROADMAP section 8:
# ECHOcommunity's Resource id for a category IS this application's
# categories.id. That holds for all 14 categories the two systems have in
# common, so no mapping table is needed.
#
# Membership is not cosmetic. The GMCC selector gates on it, so a plant that
# loses its category links disappears from that tool.
#
# Additive by design: a plant's existing links are kept and missing ones added.
# Removing a link is an editorial act, not a migration one.
class EcCategoryImporter
  Result = Struct.new(:categories_created, :categories_present, :links_created,
                      :links_present, :missing_plants, :failed, :errors,
                      keyword_init: true)

  def initialize(organization:, principal:, owner_email:, apply: false)
    @organization = organization
    @principal = principal
    @owner_email = owner_email
    @apply = apply
  end

  def import(categories, membership)
    result = Result.new(categories_created: 0, categories_present: 0,
                        links_created: 0, links_present: 0, missing_plants: 0,
                        failed: 0, errors: [])
    # Categories arriving in this payload count as available even during a dry
    # run, when they have not been written yet. Otherwise a dry run silently
    # under-reports every link belonging to a category it is about to create --
    # 179 of them for Bamboo alone.
    @incoming_category_ids = categories.to_set { |c| c['uuid'] }
    categories.each { |row| upsert_category(row, result) }
    membership.each { |plant_uuid, ids| link_plant(plant_uuid, ids, result) }
    result
  end

  private

  def upsert_category(row, result)
    if Category.unscoped.exists?(id: row['uuid'])
      result.categories_present += 1
      return
    end
    result.categories_created += 1
    create_category(row) if @apply
  rescue StandardError => e
    result.failed += 1
    result.categories_created -= 1
    result.errors << "category #{row['uuid']}: #{e.class}: #{e.message}"
  end

  # Build then save: name is a required translated attribute, so create! would
  # validate before apply_translations has had a chance to set it.
  def create_category(row)
    category = Category.new(category_attributes(row))
    apply_translations(category, row['translations'])
    category.save!
  end

  def category_attributes(row)
    { id: row['uuid'], owned_by: @owner_email, created_by: @owner_email,
      visibility: :public, owner_organization_id: @organization.id,
      source_organization_id: @organization.id,
      created_by_principal_id: @principal.id }
  end

  def apply_translations(category, translations)
    (translations || {}).each do |locale, values|
      Mobility.with_locale(locale) do
        category.name = values['name'] if values['name'].present?
        category.description = values['description'] if values['description'].present?
      end
    end
  end

  def link_plant(plant_uuid, category_ids, result)
    plant = Plant.unscoped.find_by(id: plant_uuid)
    return result.missing_plants += 1 if plant.nil?

    existing = plant.category_ids
    category_ids.each { |cid| link(plant, cid, existing, result) }
  rescue StandardError => e
    result.failed += 1
    result.errors << "plant #{plant_uuid}: #{e.class}: #{e.message}"
  end

  def known_category?(category_id)
    @incoming_category_ids.include?(category_id) ||
      Category.unscoped.exists?(id: category_id)
  end

  def link(plant, category_id, existing, result)
    return result.links_present += 1 if existing.include?(category_id)
    return unless known_category?(category_id)

    result.links_created += 1
    plant.categories << Category.unscoped.find(category_id) if @apply
  end
end
