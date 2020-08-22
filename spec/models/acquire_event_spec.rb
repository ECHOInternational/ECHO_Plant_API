# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AcquireEvent, type: :model do
  it 'is valid with valid attributes' do
    acquire_event = build(:acquire_event)
    expect(acquire_event).to be_valid
  end

  it 'is not valid without a specimen' do
    acquire_event = build(:acquire_event, specimen: nil)
    expect(acquire_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    acquire_event = build(:acquire_event, datetime: nil)
    expect(acquire_event).to_not be_valid
  end

  # Specific To this type
  
  it 'is not valid without a condition' do
    acquire_event = build(:acquire_event, condition: nil)
    expect(acquire_event).to_not be_valid
  end
  it 'is not valid without a source' do
    acquire_event = build(:acquire_event, source: nil)
    expect(acquire_event).to_not be_valid
  end
end
