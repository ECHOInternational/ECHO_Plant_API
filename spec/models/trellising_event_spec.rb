# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrellisingEvent, type: :model do
  it 'is valid with valid attributes' do
    trellising_event = build(:trellising_event)
    expect(trellising_event).to be_valid
  end

  it 'is not valid without a specimen' do
    trellising_event = build(:trellising_event, specimen: nil)
    expect(trellising_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    trellising_event = build(:trellising_event, datetime: nil)
    expect(trellising_event).to_not be_valid
  end

  # Specific To this type
end
