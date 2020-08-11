# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
output = []
Resource.where(resourceable_type: 'Plant::Category').each do |category|
  item = { uuid: category.id, translations: [] }
  category.translations.each do |translation|
    item[:translations] << { locale: translation.locale, name: translation.name, description: translation.description }
  end
  output << item
end
File.open('Categories.json', 'w') do |f|
  f.write(output.to_json)
end
