class Category < ApplicationRecord
  extend Mobility
  translates :name, :description
  validates :name, :owned_by, :created_by, :visibility, presence: true
  enum visibility: {private: 0, public: 1, draft: 2, deleted: 3}, _prefix: :visibility
end
