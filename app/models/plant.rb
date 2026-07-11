# frozen_string_literal: true

# Defines the Plant object type
class Plant < ApplicationRecord # rubocop:disable Metrics/ClassLength
  # Rails 7.2 deprecates the keyword-definition form (enum name: {...}, removed
  # in Rails 8.0); the positional form is the supported syntax on Ruby 3.3.
  enum :early_growth_phase, { slow: 'slow', intermediate: 'intermediate', fast: 'fast' }
  enum :life_cycle, { annual: 'annual', biennial: 'biennial', perennial: 'perennial' }
  validates :owned_by, :created_by, :visibility, presence: true
  enum :visibility, { private: 0, public: 1, draft: 2, deleted: 3 }, prefix: :visibility
  has_many :images, as: :imageable, dependent: :destroy

  has_many :antinutrients_plants, dependent: :destroy
  has_many :antinutrients, through: :antinutrients_plants

  has_many :categories_plants, dependent: :destroy
  has_many :categories, through: :categories_plants

  has_many :growth_habits_plants, dependent: :destroy
  has_many :growth_habits, through: :growth_habits_plants

  has_many :tolerances_plants, dependent: :destroy
  has_many :tolerances, through: :tolerances_plants

  has_many :common_names, dependent: :destroy

  has_many :varieties, dependent: :restrict_with_error

  has_many :specimens, dependent: :restrict_with_error

  # default_scope { includes(:common_names) }

  extend Mobility
  translates :description,
             :info_sheet_description,
             :origin,
             :uses,
             :cultivation,
             :harvesting_and_seed_production,
             :pests_and_diseases,
             :cooking_and_nutrition,
             :attribution,
             :edible_green_leaves_note,
             :edible_immature_fruit_note,
             :edible_mature_fruit_note,
             :used_for_fodder_note,
             :tolerance_note,
             :antinutrient_note,
             :seeding_rate,
             :planting_instructions,
             :asia_regional_info,
             :life_cycle_note,
             :n_accumulation_note,
             :biomass_production_note,
             :optimal_temperature_note,
             :optimal_rainfall_note,
             :seasonality_note,
             :early_growth_phase_note,
             :altitude_note,
             :ph_note,
             :growth_habits_note

  def genus
    return unless scientific_name

    scientific_name.split[0]
  end

  def common_names_for_locale(locale, with_primary: true)
    if with_primary
      common_names.where(language: locale.upcase).where(primary: false)
    else
      common_names.where(language: locale.upcase)
    end
  end

  # Resolves the display name for a plant in +locale+, applying a fixed
  # fallback precedence (highest priority first):
  #   1. requested language, primary == true
  #   2. 'EN', primary == true
  #   3. 'EN', any (primary true or false)
  #   4. nil
  # Within each tier the first match wins. "First" means ActiveRecord's
  # implicit primary-key ordering (ORDER BY common_names.id ASC), because the
  # underlying association queries call bare +.first+ with no explicit order.
  #
  # When the common_names association is already loaded (list/eager-loaded
  # contexts), the tiers are resolved entirely in Ruby over the in-memory
  # array — zero SQL — while reproducing the same precedence and ordering as
  # the SQL path. When it is not loaded, the original per-tier SQL is used so
  # single-record contexts are not forced to load the full association.
  def primary_common_name_for_locale(locale)
    if common_names.loaded?
      primary_common_name_from_loaded(locale)
    else
      primary_common_name_from_sql(locale)
    end
  end

  def primary_common_name
    primary_common_name_for_locale(Mobility.locale)
  end

  def translations_array # rubocop:disable all
    translations.map do |language, attributes| # rubocop:disable Metrics/BlockLength
      {
        locale: language,
        description: attributes['description'],
        info_sheet_description: attributes['info_sheet_description'],
        origin: attributes['origin'],
        uses: attributes['uses'],
        cultivation: attributes['cultivation'],
        harvesting_and_seed_production: attributes['harvesting_and_seed_production'],
        pests_and_diseases: attributes['pests_and_diseases'],
        cooking_and_nutrition: attributes['cooking_and_nutrition'],
        attribution: attributes['attribution'],
        edible_green_leaves_note: attributes['edible_green_leaves_note'],
        edible_immature_fruit_note: attributes['edible_immature_fruit_note'],
        edible_mature_fruit_note: attributes['edible_mature_fruit_note'],
        used_for_fodder_note: attributes['used_for_fodder_note'],
        tolerance_note: attributes['tolerance_note'],
        antinutrient_note: attributes['antinutrient_note'],
        seeding_rate: attributes['seeding_rate'],
        planting_instructions: attributes['planting_instructions'],
        asia_regional_info: attributes['asia_regional_info'],
        life_cycle_note: attributes['life_cycle_note'],
        n_accumulation_note: attributes['n_accumulation_note'],
        biomass_production_note: attributes['biomass_production_note'],
        optimal_temperature_note: attributes['optimal_temperature_note'],
        optimal_rainfall_note: attributes['optimal_rainfall_note'],
        seasonality_note: attributes['seasonality_note'],
        early_growth_phase_note: attributes['early_growth_phase_note'],
        altitude_note: attributes['altitude_note'],
        ph_note: attributes['ph_note'],
        growth_habits_note: attributes['growth_habits_note']
      }
    end
  end

  private

  # SQL path: preserves the original behavior exactly. Each tier runs its own
  # query and relies on ActiveRecord's implicit primary-key ordering for +.first+.
  def primary_common_name_from_sql(locale)
    requested = common_names.where(language: locale.upcase).where(primary: true).first
    return requested.name if requested

    fallback = common_names.where(language: 'EN').where(primary: true).first
    return fallback.name if fallback

    default = common_names.where(language: 'EN').first
    return default.name if default

    nil
  end

  # Loaded path: resolves the same tiers over the in-memory association with
  # zero SQL. +min_by(&:id)+ reproduces the SQL path's implicit ORDER BY id ASC
  # so the chosen record (and thus the returned name) is byte-identical.
  def primary_common_name_from_loaded(locale)
    names = common_names.to_a
    requested_lang = locale.to_s.upcase

    requested = names.select { |cn| cn.language == requested_lang && cn.primary }.min_by(&:id)
    return requested.name if requested

    en = names.select { |cn| cn.language == 'EN' }
    fallback = en.select(&:primary).min_by(&:id)
    return fallback.name if fallback

    default = en.min_by(&:id)
    return default.name if default

    nil
  end
end
