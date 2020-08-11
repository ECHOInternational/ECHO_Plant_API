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
  record = Category.new(id: category['uuid'], owned_by: 'echo@echonet.org', created_by: 'echo@echonet.org', visibility: :public)
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
