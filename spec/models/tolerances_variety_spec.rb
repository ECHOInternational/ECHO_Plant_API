# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TolerancesVariety, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:tolerances_variety)
    expect(join_record).to be_valid
  end
  it 'is not valid without a variety' do
    join_record = build(:tolerances_variety, variety: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an tolerance' do
    join_record = build(:tolerances_variety, tolerance: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    variety = create(:variety)
    tolerance = create(:tolerance)
    expect { variety.tolerances << tolerance }.to_not raise_error
    expect { variety.tolerances << tolerance }.to raise_error
  end
end
