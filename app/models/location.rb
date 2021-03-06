# frozen_string_literal: true

# Locations can belong to life cycle events and provide a reusable location for a plant specimen
class Location < ApplicationRecord
  validates :name, :owned_by, :created_by, :visibility, :soil_quality, presence: true
  enum visibility: { private: 0, public: 1, draft: 2, deleted: 3 }, _prefix: :visibility
  enum soil_quality: { poor: 'poor', fair: 'fair', good: 'good' }, _prefix: :soil_quality

  has_many :images, as: :imageable, dependent: :destroy
  has_many :life_cycle_events, dependent: :restrict_with_error

  def latitude=(latitude)
    if latlng.class == ActiveRecord::Point
      latlng.x = latitude
    else
      self.latlng = ActiveRecord::Point.new(latitude, 0)
    end
  end

  def latitude
    latlng&.x
  end

  def longitude=(longitude)
    if latlng.class == ActiveRecord::Point
      latlng.y = longitude
    else
      self.latlng = ActiveRecord::Point.new(0, longitude)
    end
  end

  def longitude
    latlng&.y
  end
end
