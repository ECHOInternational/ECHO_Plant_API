# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
output = []
Plant::Tolerance.all.each do |tolerance|
  item = { uuid: SecureRandom.uuid, id: tolerance.id, translations: [] }
  tolerance.translations.each do |translation|
    item[:translations] << { locale: translation.locale, name: translation.name }
  end
  output << item
end
File.open('Tolerances.json', 'w') do |f|
  f.write(output.to_json)
end
