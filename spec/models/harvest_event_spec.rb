# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HarvestEvent, type: :model do
  it 'is valid with valid attributes' do
    harvest_event = build(:harvest_event)
    expect(harvest_event).to be_valid
  end

  it 'is not valid without a specimen' do
    harvest_event = build(:harvest_event, specimen: nil)
    expect(harvest_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    harvest_event = build(:harvest_event, datetime: nil)
    expect(harvest_event).to_not be_valid
  end

  # Specific To this type

  it 'is not valid without a quantity' do
    harvest_event = build(:harvest_event, quantity: nil)
    expect(harvest_event).to_not be_valid
  end
  it 'is not valid without a unit' do
    harvest_event = build(:harvest_event, unit: nil)
    expect(harvest_event).to_not be_valid
  end
  it 'is not valid without a quality' do
    harvest_event = build(:harvest_event, quality: nil)
    expect(harvest_event).to_not be_valid
  end
end
