# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PruningEvent, type: :model do
  it 'is valid with valid attributes' do
    pruning_event = build(:pruning_event)
    expect(pruning_event).to be_valid
  end

  it 'is not valid without a specimen' do
    pruning_event = build(:pruning_event, specimen: nil)
    expect(pruning_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    pruning_event = build(:pruning_event, datetime: nil)
    expect(pruning_event).to_not be_valid
  end

  # Specific To this type

end
