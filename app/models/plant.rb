# frozen_string_literal: true

# Defines the Plant object type
class Plant < ApplicationRecord # rubocop:disable Metrics/ClassLength
  enum early_growth_phase: { slow: 'slow', intermediate: 'intermediate', fast: 'fast' }
  enum life_cycle: { annual: 'annual', biennial: 'biennial', perennial: 'perennial' }
  validates :owned_by, :created_by, :visibility, presence: true
  enum visibility: { private: 0, public: 1, draft: 2, deleted: 3 }, _prefix: :visibility
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

  default_scope { includes(:common_names) }

  extend Mobility
  translates :description,
             :info_sheet_description,
             :origin,
             :uses,
             :cultivation,
             :harvesting_and_seed_production,
             :pests_and_diseases,
             :cooking_and_nutrition,
             :varieties,
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

  def primary_common_name_for_locale(locale)
    requested = common_names.where(language: locale.upcase).where(primary: true).first
    return requested.name if requested

    fallback = common_names.where(language: 'EN').where(primary: true).first
    return fallback.name if fallback

    default = common_names.where(language: 'EN').first
    return default.name if default

    nil
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
        varieties: attributes['varieties'],
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
end
