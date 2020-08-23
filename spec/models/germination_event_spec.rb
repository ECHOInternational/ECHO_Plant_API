# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GerminationEvent, type: :model do
  it 'is valid with valid attributes' do
    germination_event = build(:germination_event)
    expect(germination_event).to be_valid
  end

  it 'is not valid without a specimen' do
    germination_event = build(:germination_event, specimen: nil)
    expect(germination_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    germination_event = build(:germination_event, datetime: nil)
    expect(germination_event).to_not be_valid
  end

  # Specific To this type

end
