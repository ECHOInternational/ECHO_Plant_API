# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SoilPreparationEvent, type: :model do
  it 'is valid with valid attributes' do
    soil_preparation_event = build(:soil_preparation_event)
    expect(soil_preparation_event).to be_valid
  end

  it 'is not valid without a specimen' do
    soil_preparation_event = build(:soil_preparation_event, specimen: nil)
    expect(soil_preparation_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    soil_preparation_event = build(:soil_preparation_event, datetime: nil)
    expect(soil_preparation_event).to_not be_valid
  end

  # Specific To this type

  it 'is not valid without a soil_preparation' do
    soil_preparation_event = build(:soil_preparation_event, soil_preparation: nil)
    expect(soil_preparation_event).to_not be_valid
  end
end
