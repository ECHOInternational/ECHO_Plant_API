# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
output = []

def range_value_converter(min, max)
  return nil unless min && max

  min..max
end

Resource.where(resourceable_type: 'Plant').each do |plant_resource| # rubocop:disable Metrics/BlockLength
  plant = plant_resource.resourceable
  item = {
    uuid: plant_resource.id,
    translations: {},
    common_names: {},
    scientific_name: plant.latin_name,
    family_names: plant.family_names,
    has_edible_green_leaves: plant.has_edible_green_leaves,
    has_edible_immature_fruit: plant.has_edible_immature_fruit,
    has_edible_mature_fruit: plant.has_edible_mature_fruit,
    can_be_used_for_fodder: plant.can_be_used_for_fodder,
    n_accumulation_range: range_value_converter(plant.n_accumulation_min, plant.n_accumulation_max),
    biomass_production_range: range_value_converter(plant.biomass_production_min, plant.biomass_production_max),
    optimal_temperature_range: range_value_converter(plant.temperature_min, plant.temperature_max),
    optimal_rainfall_range: range_value_converter(plant.rainfall_min, plant.rainfall_max),
    optimal_altitude_range: range_value_converter(plant.altitude_min, plant.altitude_max),
    seasonality_days_range: range_value_converter(plant.seasonality_days_min, plant.seasonality_days_max),
    ph_range: range_value_converter(plant.ph_min, plant.ph_max),
    early_growth_phase: plant.early_growth_phase,
    life_cycle: plant.life_cycle
  }

  plant.translations.each do |translation| # rubocop:disable Metrics/BlockLength
    item[:translations][translation.locale] = {
      locale: translation.locale,
      info_sheet_description: translation.description,
      origin: translation.origin,
      uses: translation.uses,
      cultivation: translation.cultivation,
      harvesting_and_seed_production: translation.harvesting_and_seed_production,
      pests_and_diseases: translation.pests_and_diseases,
      cooking_and_nutrition: translation.cooking_and_nutrition,
      varieties: translation.varieties,
      attribution: translation.attribution,
      edible_green_leaves_note: translation.edible_green_leaves_note,
      edible_immature_fruit_note: translation.edible_immature_fruit_note,
      edible_mature_fruit_note: translation.edible_mature_fruit_note,
      used_for_fodder_note: translation.used_for_fodder_note,
      tolerance_note: translation.tolerance_note,
      antinutrient_note: translation.antinutrient_note,
      seeding_rate: translation.seeding_rate,
      planting_instructions: translation.planting_instructions,
      asia_regional_info: translation.asia_regional_info,
      life_cycle_note: translation.life_cycle_note,
      n_accumulation_note: translation.n_accumulation_note,
      biomass_production_note: translation.biomass_production_note,
      optimal_temperature_note: translation.temperature_note,
      optimal_rainfall_note: translation.rainfall_note,
      seasonality_note: translation.seasonality_note,
      early_growth_phase_note: translation.early_growth_phase_note,
      altitude_note: translation.altitude_note,
      ph_note: translation.ph_note,
      growth_habits_note: translation.growth_habits_note
    }
  end

  plant_resource.translations.each do |translation|
    item[:translations][translation.locale][:description] = translation.description
    item[:translations][translation.locale][:primary_common_name] = translation.name
  end

  plant.common_names.each do |common_name|
    item[:common_names][common_name.language] ||= []
    item[:common_names][common_name.language] << { name: common_name.name, location: common_name.location }
  end

  output << item
end
File.open('Plants.json', 'w') do |f|
  f.write(output.to_json)
end
