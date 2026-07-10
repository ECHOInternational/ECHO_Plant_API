# frozen_string_literal: true

# Life cycle events are ordered events that chronicle the crop management of a plant specimen
class LifeCycleEvent < ApplicationRecord
  validates :type, :specimen, :datetime, presence: true
  # Ruby 3.1/Psych-4 rung: a bare hash as the last positional arg to enum (which
  # takes **options) is an ambiguous-kwargs deprecation on 2.7 and mis-binds on 3.x.
  # Use the Rails 7 keyword-definition form (enum name: {...}) for enums with no
  # trailing option kwarg; behaviour is identical.
  enum condition: { poor: 'poor', fair: 'fair', good: 'good' }
  enum :unit, { weight: 'weight', count: 'count' }, prefix: :unit
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
  delegate :owned_by, to: :specimen
  delegate :visibility, to: :specimen
  belongs_to :location, optional: true

  def self.policy_class
    LifeCycleEventPolicy
  end
end
