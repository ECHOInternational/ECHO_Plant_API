class ImageAttribute < ApplicationRecord
  extend Mobility
  translates :name
  validates :name, presence: true
  def translations_array
  	translations.map{ |language, attributes| {locale: language, name: attributes["name"] }}
  end
end
