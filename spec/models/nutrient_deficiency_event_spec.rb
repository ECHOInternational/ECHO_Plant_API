# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NutrientDeficiencyEvent, type: :model do
  it 'is valid with valid attributes' do
    nutrient_deficiency_event = build(:nutrient_deficiency_event)
    expect(nutrient_deficiency_event).to be_valid
  end

  it 'is not valid without a specimen' do
    nutrient_deficiency_event = build(:nutrient_deficiency_event, specimen: nil)
    expect(nutrient_deficiency_event).to_not be_valid
  end

  it 'is not valid without a datetime' do
    nutrient_deficiency_event = build(:nutrient_deficiency_event, datetime: nil)
    expect(nutrient_deficiency_event).to_not be_valid
  end

  # Specific To this type

end
