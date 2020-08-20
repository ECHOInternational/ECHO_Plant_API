class LifeCycleEvent < ApplicationRecord
  validates :type, :specimen, :datetime, presence: true
  enum condition: { poor: 'poor', fair: 'fair', good: 'good' }

  has_many :images, as: :imageable, dependent: :destroy

  belongs_to :specimen
  belongs_to :location, optional: true
end
