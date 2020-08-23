# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ThinningEvent, type: :model do
  it 'is valid with valid attributes' do
    thinning_event = build(:thinning_event)
    expect(thinning_event).to be_valid
  end

  it 'is not valid without a specimen' do
    thinning_event = build(:thinning_event, specimen: nil)
    expect(thinning_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    thinning_event = build(:thinning_event, datetime: nil)
    expect(thinning_event).to_not be_valid
  end

  # Specific To this type

end
