# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MulchingEvent, type: :model do
  it 'is valid with valid attributes' do
    mulching_event = build(:mulching_event)
    expect(mulching_event).to be_valid
  end

  it 'is not valid without a specimen' do
    mulching_event = build(:mulching_event, specimen: nil)
    expect(mulching_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    mulching_event = build(:mulching_event, datetime: nil)
    expect(mulching_event).to_not be_valid
  end

  # Specific To this type
end
