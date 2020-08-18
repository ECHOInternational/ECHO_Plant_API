# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
output = {
  categories: [],
  antinutrients: [],
  tolerances: [],
  growth_habits: []
}

# Categories already have access to both ids
Plant::CategoriesPlant.all.each do |relation|
  next unless relation.plant
  next unless relation.plant_category
  next unless relation.plant.resource
  next unless relation.plant_category.resource

  output[:categories] << {
    plant_id: relation.plant.resource.id,
    category_id: relation.plant_category.resource.id
  }
end

# Antinutrients don't have UUIDs in the old API,
# We'll have to look them up later
Plant::AntinutrientsPlant.all.each do |relation|
  next unless relation.plant
  next unless relation.plant.resource

  output[:antinutrients] << {
    plant_id: relation.plant.resource.id,
    antinutrient_id: relation.plant_antinutrient_id
  }
end

Plant::TolerancesPlant.all.each do |relation|
  next unless relation.plant
  next unless relation.plant.resource

  output[:tolerances] << {
    plant_id: relation.plant.resource.id,
    tolerance_id: relation.plant_tolerance_id
  }
end

Plant::GrowthHabitsPlant.all.each do |relation|
  next unless relation.plant
  next unless relation.plant.resource

  output[:growth_habits] << {
    plant_id: relation.plant.resource.id,
    growth_habit_id: relation.plant_growth_habit_id
  }
end

File.open('PlantRelationships.json', 'w') do |f|
  f.write(output.to_json)
end
