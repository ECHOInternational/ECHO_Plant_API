# frozen_string_literal: true

class Category < ApplicationRecord
  extend Mobility
  translates :name, :description
  validates :name, :owned_by, :created_by, :visibility, presence: true
  enum visibility: { private: 0, public: 1, draft: 2, deleted: 3 }, _prefix: :visibility
  has_many :images, as: :imageable, dependent: :destroy
  def translations_array
    translations.map { |language, attributes| { locale: language, name: attributes['name'], description: attributes['description'] } }
  end
end
