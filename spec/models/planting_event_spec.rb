# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlantingEvent, type: :model do
  it 'is valid with valid attributes' do
    planting_event = build(:planting_event)
    expect(planting_event).to be_valid
  end

  it 'is not valid without a specimen' do
    planting_event = build(:planting_event, specimen: nil)
    expect(planting_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    planting_event = build(:planting_event, datetime: nil)
    expect(planting_event).to_not be_valid
  end

  # Specific To this type

  it 'is not valid without a location' do
    planting_event = build(:planting_event, location: nil)
    expect(planting_event).to_not be_valid
  end
end
