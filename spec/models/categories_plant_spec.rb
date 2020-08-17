# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CategoriesPlant, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:categories_plant)
    expect(join_record).to be_valid
  end
  it 'is not valid without a plant' do
    join_record = build(:categories_plant, plant: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an category' do
    join_record = build(:categories_plant, category: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    plant = create(:plant)
    category = create(:category)
    expect { plant.categories << category }.to_not raise_error
    expect { plant.categories << category }.to raise_error
  end
end
