require 'rails_helper'

RSpec.describe AntinutrientsPlant, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:antinutrients_plant)
    expect(join_record).to be_valid
  end
  it 'is not valid without a plant' do
    join_record = build(:antinutrients_plant, plant: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an antinutrient' do
    join_record = build(:antinutrients_plant, antinutrient: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    plant = create(:plant)
    antinutrient = create(:antinutrient)
    expect { plant.antinutrients << antinutrient }.to_not raise_error
    expect { plant.antinutrients << antinutrient }.to raise_error
  end
end
