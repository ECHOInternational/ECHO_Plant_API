require 'rails_helper'

RSpec.describe TolerancesPlant, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:tolerances_plant)
    expect(join_record).to be_valid
  end
  it 'is not valid without a plant' do
    join_record = build(:tolerances_plant, plant: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an tolerance' do
    join_record = build(:tolerances_plant, tolerance: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    plant = create(:plant)
    tolerance = create(:tolerance)
    expect { plant.tolerances << tolerance }.to_not raise_error
    expect { plant.tolerances << tolerance }.to raise_error
  end
end
