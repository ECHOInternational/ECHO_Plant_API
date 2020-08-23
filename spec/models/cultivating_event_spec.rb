# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CultivatingEvent, type: :model do
  it 'is valid with valid attributes' do
    cultivating_event = build(:cultivating_event)
    expect(cultivating_event).to be_valid
  end

  it 'is not valid without a specimen' do
    cultivating_event = build(:cultivating_event, specimen: nil)
    expect(cultivating_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    cultivating_event = build(:cultivating_event, datetime: nil)
    expect(cultivating_event).to_not be_valid
  end

  # Specific To this type
end
