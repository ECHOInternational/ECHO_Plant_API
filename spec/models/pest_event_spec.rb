# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PestEvent, type: :model do
  it 'is valid with valid attributes' do
    pest_event = build(:pest_event)
    expect(pest_event).to be_valid
  end

  it 'is not valid without a specimen' do
    pest_event = build(:pest_event, specimen: nil)
    expect(pest_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    pest_event = build(:pest_event, datetime: nil)
    expect(pest_event).to_not be_valid
  end

  # Specific To this type
end
