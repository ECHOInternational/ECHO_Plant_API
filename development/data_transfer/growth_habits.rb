# frozen_string_literal: true

# Generates the output from ECHOcommunity expected by the seeds.rb file.
output = []
Plant::GrowthHabit.all.each do |growth_habit|
  item = { uuid: SecureRandom.uuid, id: growth_habit.id, translations: [] }
  growth_habit.translations.each do |translation|
    item[:translations] << { locale: translation.locale, name: translation.name }
  end
  output << item
end
File.open('GrowthHabits.json', 'w') do |f|
  f.write(output.to_json)
end
