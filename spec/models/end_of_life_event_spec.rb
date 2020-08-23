# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EndOfLifeEvent, type: :model do
  it 'is valid with valid attributes' do
    end_of_life_event = build(:end_of_life_event)
    expect(end_of_life_event).to be_valid
  end

  it 'is not valid without a specimen' do
    end_of_life_event = build(:end_of_life_event, specimen: nil)
    expect(end_of_life_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    end_of_life_event = build(:end_of_life_event, datetime: nil)
    expect(end_of_life_event).to_not be_valid
  end

  # Specific To this type

end
