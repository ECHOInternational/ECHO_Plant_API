# frozen_string_literal: true

# Life cycle events are ordered events that chronicle the crop management of a plant specimen
class LifeCycleEvent < ApplicationRecord
  validates :type, :specimen, :datetime, presence: true
  enum condition: { poor: 'poor', fair: 'fair', good: 'good' }
  enum unit: { weight: 'weight', count: 'count' }, _prefix: :unit
  enum soil_preparation: {
    greenhouse: 'greenhouse',
    planting_station: 'planting_station',
    no_till: 'no_till',
    full_till: 'full_till',
    raised_beds: 'raised_beds',
    vertical_garden: 'vertical_garden',
    container: 'container',
    other: 'other'
  }

  has_many :images, as: :imageable, dependent: :destroy

  belongs_to :specimen
  belongs_to :location, optional: true
end
