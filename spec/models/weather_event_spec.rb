# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WeatherEvent, type: :model do
  it 'is valid with valid attributes' do
    weather_event = build(:weather_event)
    expect(weather_event).to be_valid
  end

  it 'is not valid without a specimen' do
    weather_event = build(:weather_event, specimen: nil)
    expect(weather_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    weather_event = build(:weather_event, datetime: nil)
    expect(weather_event).to_not be_valid
  end

  # Specific To this type

end
