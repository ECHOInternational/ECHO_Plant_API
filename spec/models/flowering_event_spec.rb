# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FloweringEvent, type: :model do
  it 'is valid with valid attributes' do
    flowering_event = build(:flowering_event)
    expect(flowering_event).to be_valid
  end

  it 'is not valid without a specimen' do
    flowering_event = build(:flowering_event, specimen: nil)
    expect(flowering_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    flowering_event = build(:flowering_event, datetime: nil)
    expect(flowering_event).to_not be_valid
  end

  # Specific To this type
end
