# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WeedManagementEvent, type: :model do
  it 'is valid with valid attributes' do
    weed_management_event = build(:weed_management_event)
    expect(weed_management_event).to be_valid
  end

  it 'is not valid without a specimen' do
    weed_management_event = build(:weed_management_event, specimen: nil)
    expect(weed_management_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    weed_management_event = build(:weed_management_event, datetime: nil)
    expect(weed_management_event).to_not be_valid
  end

  # Specific To this type
end
