# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
output = []
Plant::Antinutrient.all.each do |antinutrient|
  item = { uuid: SecureRandom.uuid, id: antinutrient.id, translations: [] }
  antinutrient.translations.each do |translation|
    item[:translations] << { locale: translation.locale, name: translation.name }
  end
  output << item
end
File.open('Antinutrients.json', 'w') do |f|
  f.write(output.to_json)
end
