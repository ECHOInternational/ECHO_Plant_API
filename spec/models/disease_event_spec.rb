# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DiseaseEvent, type: :model do
  it 'is valid with valid attributes' do
    disease_event = build(:disease_event)
    expect(disease_event).to be_valid
  end

  it 'is not valid without a specimen' do
    disease_event = build(:disease_event, specimen: nil)
    expect(disease_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    disease_event = build(:disease_event, datetime: nil)
    expect(disease_event).to_not be_valid
  end

  # Specific To this type
end
