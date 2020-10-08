# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

# Categories
categories_json = File.read('db/seeds/Categories.json')
categories = JSON.parse(categories_json)
categories.each do |category|
  record = Category.new(
    id: category['uuid'],
    owned_by: 'echo@echonet.org',
    created_by: 'echo@echonet.org',
    visibility: :public
  )
  category['translations'].each do |translation|
    Mobility.with_locale(translation['locale']) do
      record.name = translation['name']
      record.description = translation['description']
    end
  end
  record.save!
end

# ImageAttributes
image_attributes_json = File.read('db/seeds/ImageAttributes.json')
image_attributes = JSON.parse(image_attributes_json)
image_attributes.each do |image_attribute|
  ImageAttribute.create!(image_attribute)
end

# Antinutrients
antinutrients_json = File.read('db/seeds/Antinutrients.json')
antinutrients = JSON.parse(antinutrients_json)
antinutrients.each do |antinutrient|
  record = Antinutrient.new(
    id: antinutrient['uuid']
  )
  antinutrient['translations'].each do |translation|
    Mobility.with_locale(translation['locale']) do
      record.name = translation['name']
    end
  end
  record.save!
end

# Tolerances
tolerances_json = File.read('db/seeds/Tolerances.json')
tolerances = JSON.parse(tolerances_json)
tolerances.each do |tolerance|
  record = Tolerance.new(
    id: tolerance['uuid']
  )
  tolerance['translations'].each do |translation|
    Mobility.with_locale(translation['locale']) do
      record.name = translation['name']
    end
  end
  record.save!
end

# Growth Habits
growth_habits_json = File.read('db/seeds/GrowthHabits.json')
growth_habits = JSON.parse(growth_habits_json)
growth_habits.each do |growth_habit|
  record = GrowthHabit.new(
    id: growth_habit['uuid']
  )
  growth_habit['translations'].each do |translation|
    Mobility.with_locale(translation['locale']) do
      record.name = translation['name']
    end
  end
  record.save!
end

# Plants
plants_json = File.read('db/seeds/Plants.json')
plants = JSON.parse(plants_json)
plants.each do |plant| # rubocop:disable Metrics/BlockLength
  attributes = {}
  attributes[:id] = plant['uuid']
  attributes[:scientific_name] = plant['scientific_name'] unless plant['scientific_name'].nil?
  attributes[:family_names] = plant['family_names'] unless plant['family_names'].nil?
  attributes[:has_edible_green_leaves] = plant['has_edible_green_leaves'] unless plant['has_edible_green_leaves'].nil?
  attributes[:has_edible_immature_fruit] = plant['has_edible_immature_fruit'] unless plant['has_edible_immature_fruit'].nil?
  attributes[:has_edible_mature_fruit] = plant['has_edible_mature_fruit'] unless plant['has_edible_mature_fruit'].nil?
  attributes[:can_be_used_for_fodder] = plant['can_be_used_for_fodder'] unless plant['can_be_used_for_fodder'].nil?
  attributes[:n_accumulation_range] = eval(plant['n_accumulation_range']) unless plant['n_accumulation_range'].nil?
  attributes[:biomass_production_range] = eval(plant['biomass_production_range']) unless plant['biomass_production_range'].nil?
  attributes[:optimal_temperature_range] = eval(plant['optimal_temperature_range']) unless plant['optimal_temperature_range'].nil?
  attributes[:optimal_rainfall_range] = eval(plant['optimal_rainfall_range']) unless plant['optimal_rainfall_range'].nil?
  attributes[:optimal_altitude_range] = eval(plant['optimal_altitude_range']) unless plant['optimal_altitude_range'].nil?
  attributes[:seasonality_days_range] = eval(plant['seasonality_days_range']) unless plant['seasonality_days_range'].nil?
  attributes[:ph_range] = eval(plant['ph_range']) unless plant['ph_range'].nil?
  attributes[:early_growth_phase] = plant['early_growth_phase'] unless plant['early_growth_phase'].nil?
  attributes[:life_cycle] = plant['life_cycle'] unless plant['life_cycle'].nil?
  attributes[:owned_by] = 'echo@echonet.org'
  attributes[:created_by] = 'echo@echonet.org'
  attributes[:visibility] = :public

  record = Plant.new(attributes)

  primary_common_names = {}

  plant['translations'].each do |_language, values|
    locale = values.delete('locale')
    pcn = values.delete('primary_common_name')
    primary_common_names[locale] = pcn.downcase if pcn

    Mobility.with_locale(locale) do
      values.each do |key, value|
        record.send("#{key}=", value) unless value.blank?
      end
    rescue NoMethodError
      # Do nothing
    end
  end
  record.save!

  plant['common_names'].each do |language, cns|
    cns.each do |cn|
      is_primary = primary_common_names[language.downcase] == cn['name'].downcase
      CommonName.create(plant: record, language: language, name: cn['name'], location: cn['location'], primary: is_primary)
    end
  end
end

# Relationships
relationships_json = File.read('db/seeds/PlantRelationships.json')
relationships = JSON.parse(relationships_json)

# Plants - Categories
relationships['categories'].each do |cat|
  CategoriesPlant.create(cat)
end

# Plants - Antinutrients (19)
relationships['antinutrients'].each do |an|
  lookup = antinutrients.detect { |a| a['id'] == an['antinutrient_id'] }
  next unless lookup

  AntinutrientsPlant.create(antinutrient_id: lookup['uuid'], plant_id: an['plant_id'])
end

# Plants - Tolerances
relationships['tolerances'].each do |tn|
  lookup = tolerances.detect { |t| t['id'] == tn['tolerance_id'] }
  next unless lookup

  TolerancesPlant.create(tolerance_id: lookup['uuid'], plant_id: tn['plant_id'])
end

# Plants - Growth Habits
relationships['growth_habits'].each do |gh|
  lookup = growth_habits.detect { |g| g['id'] == gh['growth_habit_id'] }
  next unless lookup

  GrowthHabitsPlant.create(growth_habit_id: lookup['uuid'], plant_id: gh['plant_id'])
end

# Images for Plants
require 'csv'
CSV.foreach('db/seeds/Images_For_Plants.csv', headers: true) do |row|
  plant = Plant.find row['uuid']

  Image.create(
    {
      id: SecureRandom.uuid,
      imageable: plant,
      name: row['FileName'],
      owned_by: 'echo@echonet.org',
      created_by: 'echo@echonet.org',
      visibility: :public,
      attribution: row['attribution'],
      s3_key: row['s3_key'].gsub(' ', '_'),
      s3_bucket: 'images-us-east-1.echocommunity.org'
    }
  )
end

# Varieties
varieties_json = File.read('db/seeds/Varieties.json')
varieties = JSON.parse(varieties_json)
varieties.each do |variety|
  next if variety['visibility'] == 'deleted'

  variety['visibility'] = 'public' if variety['visibility'] == 'published'
  variety['owned_by'] = 'echo@echonet.org'
  variety['created_by'] = 'echo@echonet.org'

  record = Variety.new(variety.except('translations'))
  variety['translations'].each do |language, values|
    Mobility.with_locale(language) do
      record.name = values['name']
      record.description = values['description'] if values['description'].present?
      record.planting_instructions = values['planting_instructions'] if values['planting_instructions'].present?
    end
  end
  record.save!
end

# Images for Varieties
require 'csv'
CSV.foreach('db/seeds/Images_For_Varieties.csv', headers: true) do |row|
  variety = Variety.find row['uuid']

  Image.create(
    {
      id: SecureRandom.uuid,
      imageable: variety,
      name: row['FileName'],
      owned_by: 'echo@echonet.org',
      created_by: 'echo@echonet.org',
      visibility: :public,
      attribution: row['attribution'],
      s3_key: row['s3_key'].gsub(' ', '_'),
      s3_bucket: 'images-us-east-1.echocommunity.org'
    }
  )
end
