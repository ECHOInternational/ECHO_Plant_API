# frozen_string_literal: true

# Syncs common names from ECHOcommunity and sets the `primary` flag per
# language during the plant-data ownership migration.
#
# Why `primary` matters: the API only uses a language when a primary is set in
# it, otherwise falling back to English (Plant#primary_common_name_for_locale).
# A language with names but no primary therefore shows English, so a Malay
# reader sees an English name while Malay names sit unused in the same table.
#
# Which name is primary is decided upstream, in the migration workspace, where
# the rules and their reasoning live together. This class applies that decision.
#
# Additive for names: missing names are created, existing ones are matched
# case-insensitively on (name, language) and never duplicated. Deleting a name
# ECHOcommunity no longer lists is an editorial act, not a migration one.
class EcCommonNameSync
  Result = Struct.new(:created, :present, :primary_set, :primary_cleared,
                      :recased, :missing_plants, :failed, :errors,
                      keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def sync(plants)
    result = Result.new(created: 0, present: 0, primary_set: 0,
                        primary_cleared: 0, recased: 0, missing_plants: 0,
                        failed: 0, errors: [])
    plants.each { |uuid, names| sync_plant(uuid, names, result) }
    result
  end

  private

  def sync_plant(plant_uuid, names, result)
    plant = Plant.unscoped.find_by(id: plant_uuid)
    return result.missing_plants += 1 if plant.nil?

    existing = plant.common_names.index_by { |cn| key(cn.name, cn.language) }
    names.each { |row| sync_name(plant, row, existing, result) }
  rescue StandardError => e
    record_failure(plant_uuid, e, result)
  end

  def record_failure(plant_uuid, error, result)
    result.failed += 1
    result.errors << "plant #{plant_uuid}: #{error.class}: #{error.message}"
  end

  def sync_name(plant, row, existing, result)
    record = existing[key(row['name'], row['language'])]
    record ? update_primary(record, row, result) : create_name(plant, row, result)
  end

  def create_name(plant, row, result)
    result.created += 1
    result.primary_set += 1 if row['primary']
    return unless @apply

    CommonName.create!(plant: plant, name: row['name'], language: row['language'],
                       location: row['location'], primary: row['primary'] || false)
  end

  def update_primary(record, row, result)
    result.present += 1
    changes = recase(record, row, result).merge(reflag(record, row, result))
    record.update!(changes) if @apply && changes.any?
  end

  # Names match case-insensitively, so "Velvet Bean" and "velvet bean" are the
  # same name. ECHOcommunity's casing is the curated one, so adopt it rather
  # than leaving the API holding a variant that gets pushed back later.
  def recase(record, row, result)
    return {} if record.name == row['name']

    result.recased += 1
    { name: row['name'] }
  end

  def reflag(record, row, result)
    wanted = row['primary'] || false
    return {} if record.primary == wanted

    wanted ? result.primary_set += 1 : result.primary_cleared += 1
    { primary: wanted }
  end

  def key(name, language)
    [name.to_s.strip.downcase, language.to_s.strip.upcase]
  end
end
