# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OtherEvent, type: :model do
  it 'is valid with valid attributes' do
    other_event = build(:other_event)
    expect(other_event).to be_valid
  end

  it 'is not valid without a specimen' do
    other_event = build(:other_event, specimen: nil)
    expect(other_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    other_event = build(:other_event, datetime: nil)
    expect(other_event).to_not be_valid
  end

  # Specific To this type

end
