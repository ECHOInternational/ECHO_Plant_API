# frozen_string_literal: true

# Imports plants exported from ECHOcommunity during the plant-data ownership
# migration.
#
# Consumes the same JSON shape as db/seeds/Plants.json, so the export tooling
# targets a format this application already understands. Writes go through the
# model layer, never raw SQL, so Mobility translations, the visibility trio and
# PaperTrail all behave normally (migration decision D-016).
#
# Idempotent: a record whose uuid already exists is skipped, never overwritten.
# Bringing an existing record up to date is reconciliation, a separate concern
# with conflict handling.
class EcPlantImporter
  Result = Struct.new(:created, :skipped, :failed, :errors, keyword_init: true)

  RANGE_FIELDS = %w[
    n_accumulation_range biomass_production_range optimal_temperature_range
    optimal_rainfall_range optimal_altitude_range seasonality_days_range ph_range
  ].freeze

  SCALAR_FIELDS = %w[
    scientific_name family_names has_edible_green_leaves
    has_edible_immature_fruit has_edible_mature_fruit can_be_used_for_fodder
    early_growth_phase life_cycle
  ].freeze

  def initialize(organization:, principal:, owner_email:, apply: false)
    @organization = organization
    @principal = principal
    @owner_email = owner_email
    @apply = apply
  end

  def import(records)
    result = Result.new(created: 0, skipped: 0, failed: 0, errors: [])
    records.each { |row| import_row(row, result) }
    result
  end

  # "25..32" -> 25..32, "5.0..7.0" -> 5.0..7.0. The seed task used eval for
  # this; parsing avoids executing data.
  def self.parse_range(str)
    return nil if str.blank?

    lo, hi = str.split('..', 2)
    return nil if hi.nil?

    return Range.new(lo.to_f, hi.to_f) if lo.include?('.') || hi.include?('.')

    Range.new(lo.to_i, hi.to_i)
  end

  private

  def import_row(row, result)
    return result.skipped += 1 if Plant.unscoped.exists?(id: row['uuid'])
    return result.created += 1 unless @apply

    persist(row)
    result.created += 1
  rescue StandardError => e
    result.failed += 1
    result.errors << "#{row['uuid']} (#{row['scientific_name']}): #{e.class}: #{e.message}"
  end

  def persist(row)
    ActiveRecord::Base.transaction do
      plant = build_plant(row)
      plant.save!
      create_common_names(plant, row)
    end
  end

  def build_plant(row)
    plant = Plant.new(base_attributes(row))
    apply_translations(plant, row)
    plant
  end

  def base_attributes(row)
    attrs = {
      id: row['uuid'], owned_by: @owner_email, created_by: @owner_email,
      visibility: :public, owner_organization_id: @organization.id,
      source_organization_id: @organization.id,
      created_by_principal_id: @principal.id
    }
    SCALAR_FIELDS.each { |f| attrs[f.to_sym] = row[f] unless row[f].nil? }
    attrs.merge(range_attributes(row))
  end

  # Assign every range unconditionally, nil included. These columns carry
  # defaults that assert facts nobody measured -- ph_range '[0.0,14.0]',
  # optimal_temperature_range '[0,61)', n_accumulation_range '[0,1)',
  # biomass_production_range '[0.0,0.0]', rainfall and altitude '[0,)'.
  # Omitting an absent range would record "tolerates pH 0-14" rather than
  # "unknown", which is how the 2020 export left 174 of 322 plants claiming
  # exactly that.
  def range_attributes(row)
    RANGE_FIELDS.index_with { |f| self.class.parse_range(row[f]) }
                .transform_keys(&:to_sym)
  end

  def apply_translations(plant, row)
    (row['translations'] || {}).each_value do |values|
      values = values.dup
      locale = values.delete('locale')
      values.delete('primary_common_name') # belongs to CommonName, not the plant
      next if locale.blank?

      Mobility.with_locale(locale) { assign_translated(plant, values) }
    end
  end

  def assign_translated(plant, values)
    values.each do |key, value|
      next if value.blank?

      plant.public_send("#{key}=", value) if plant.respond_to?("#{key}=")
    end
  end

  # The exporter records ECHOcommunity's display title per locale as
  # primary_common_name; whichever common name matches it becomes the primary
  # for that language (migration decision D-026).
  def create_common_names(plant, row)
    primaries = primary_names_by_locale(row)
    (row['common_names'] || {}).each do |language, names|
      names.each do |cn|
        next if cn['name'].blank?

        CommonName.create!(
          plant: plant, language: language, name: cn['name'],
          location: cn['location'],
          primary: primaries[language.to_s.downcase] == cn['name'].to_s.downcase
        )
      end
    end
  end

  def primary_names_by_locale(row)
    (row['translations'] || {}).each_with_object({}) do |(_k, values), acc|
      locale = values['locale']
      name = values['primary_common_name']
      acc[locale.to_s.downcase] = name.downcase if locale.present? && name.present?
    end
  end
end
