# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MovementEvent, type: :model do
  it 'is valid with valid attributes' do
    movement_event = build(:movement_event)
    expect(movement_event).to be_valid
  end

  it 'is not valid without a specimen' do
    movement_event = build(:movement_event, specimen: nil)
    expect(movement_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    movement_event = build(:movement_event, datetime: nil)
    expect(movement_event).to_not be_valid
  end

  # Specific To this type

  it 'is not valid without a location' do
    movement_event = build(:movement_event, location: nil)
    expect(movement_event).to_not be_valid
  end
end
