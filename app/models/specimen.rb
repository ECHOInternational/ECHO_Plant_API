# frozen_string_literal: true

# Specimens are individual (eg. tree) or groups (eg. row) of plants/vareities
class Specimen < ApplicationRecord
  belongs_to :plant
  belongs_to :variety, optional: true
  validates :name, :owned_by, :created_by, :visibility, presence: true
  enum visibility: { private: 0, public: 1, draft: 2, deleted: 3 }, _prefix: :visibility
  has_many :images, as: :imageable, dependent: :destroy
  has_many :life_cycle_events, dependent: :destroy
end
