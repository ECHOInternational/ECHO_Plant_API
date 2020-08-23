# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FertilizingEvent, type: :model do
  it 'is valid with valid attributes' do
    fertilizing_event = build(:fertilizing_event)
    expect(fertilizing_event).to be_valid
  end

  it 'is not valid without a specimen' do
    fertilizing_event = build(:fertilizing_event, specimen: nil)
    expect(fertilizing_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    fertilizing_event = build(:fertilizing_event, datetime: nil)
    expect(fertilizing_event).to_not be_valid
  end

  # Specific To this type
end
