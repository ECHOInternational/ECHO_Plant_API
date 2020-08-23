# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StakingEvent, type: :model do
  it 'is valid with valid attributes' do
    staking_event = build(:staking_event)
    expect(staking_event).to be_valid
  end

  it 'is not valid without a specimen' do
    staking_event = build(:staking_event, specimen: nil)
    expect(staking_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    staking_event = build(:staking_event, datetime: nil)
    expect(staking_event).to_not be_valid
  end

  # Specific To this type

end
