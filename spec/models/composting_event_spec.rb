# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompostingEvent, type: :model do
  it 'is valid with valid attributes' do
    composting_event = build(:composting_event)
    expect(composting_event).to be_valid
  end

  it 'is not valid without a specimen' do
    composting_event = build(:composting_event, specimen: nil)
    expect(composting_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    composting_event = build(:composting_event, datetime: nil)
    expect(composting_event).to_not be_valid
  end

  # Specific To this type

end
