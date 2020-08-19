# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
errors = []
output = []
Plant::Variety.all.each do |variety| # rubocop:disable Metrics/BlockLength
  resource = variety.resource
  unless resource
    errors << { resource_missing: variety.id }
    print "\e[31m.\e[0m"
    next
  end

  item = { id: resource.id, translations: {}, visibility: resource.status }
  plant = variety.plant

  unless plant
    errors << { plant_missing: variety.plant_id }
    print "\e[31m.\e[0m"
    next
  end

  unless plant.resource
    errors << { plant_resource_missing: variety.plant_id }
    print "\e[31m.\e[0m"
    next
  end

  item[:plant_id] = plant.resource.id

  variety.translations.each do |translation|
    if translation.planting_instructions.present?
      item[:translations][translation.locale] ||= {}
      item[:translations][translation.locale][:planting_instructions] = translation.planting_instructions
    end
    print "\e[32m.\e[0m"
  end

  resource.translations.each do |translation|
    item[:translations][translation.locale] ||= {}
    item[:translations][translation.locale][:name] = translation.name
    item[:translations][translation.locale][:description] = translation.description
    print "\e[32m.\e[0m"
  end

  output << item
  print "\e[32m!\e[0m"
end
File.open('Varieties.json', 'w') do |f|
  print "\e[32mWriting Varieties.json...\e[0m"
  f.write(output.to_json)
  puts "\e[32mDone.\e[0m"
end
puts errors
