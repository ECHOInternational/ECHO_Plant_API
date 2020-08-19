# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AntinutrientsVariety, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:antinutrients_variety)
    expect(join_record).to be_valid
  end
  it 'is not valid without a variety' do
    join_record = build(:antinutrients_variety, variety: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an antinutrient' do
    join_record = build(:antinutrients_variety, antinutrient: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    variety = create(:variety)
    antinutrient = create(:antinutrient)
    expect { variety.antinutrients << antinutrient }.to_not raise_error
    expect { variety.antinutrients << antinutrient }.to raise_error
  end
end
