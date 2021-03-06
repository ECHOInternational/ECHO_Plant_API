# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Category, type: :model do
  it 'is valid with valid attributes' do
    category = build(:category)
    expect(category).to be_valid
  end
  it 'is not valid without a name' do
    category = build(:category, name: nil)
    expect(category).to_not be_valid
  end
  it 'is not valid without a creator' do
    category = build(:category, created_by: nil)
    expect(category).to_not be_valid
  end
  it 'is not valid without an owner' do
    category = build(:category, owned_by: nil)
    expect(category).to_not be_valid
  end
  it "has a default visibility of 'private'" do
    category = build(:category)
    expect(category).to be_valid
    expect(category.visibility).to eq('private')
  end
  it 'can set visibility' do
    category = build(:category, :public)
    expect(category).to be_valid
    expect(category.visibility).to eq('public')
  end
  it 'translates the name attribute' do
    category = create(:category, name_en: 'name_en')
    category.name_es = 'name_es'
    expect(category.translations).to have_key(:en)
    expect(category.translations).to have_key(:es)
    expect(category.translations[:en]).to have_key(:name)
    expect(category.translations[:es]).to have_key(:name)
    expect(category.translations[:en][:name]).to eq('name_en')
    expect(category.translations[:es][:name]).to eq('name_es')
  end

  it 'is destroys all related images when it is destroyed' do
    category = create(:category)
    create(:image, imageable: category)
    expect { category.destroy }.to change { Image.count }.by(-1)
  end

  it 'is versioned' do
    is_expected.to be_versioned
    category = build(:category)
    expect(category).to respond_to(:versions)
  end

  it 'has many plants' do
    category = create(:category)
    plant_a = create(:plant)
    plant_b = create(:plant)
    expect { category.plants << plant_a }.to change { category.plants.count }.by(1)
    expect { category.plants << plant_b }.to change { category.plants.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related plants_categories records' do
      category = create(:category)
      plant = create(:plant)
      category.plants << plant
      expect { category.destroy }.to change { CategoriesPlant.count }.by(-1)
    end
    it 'does not destory related plants' do
      category = create(:category)
      plant = create(:plant)
      category.plants << plant
      expect { category.destroy }.to_not change { Plant.count }
    end
  end

  # it 'can track changes', versioning: true do
  #   expect(PaperTrail).to be_enabled
  #   category = create(:category, owned_by: 'a')
  #   category.update!(owned_by: 'b')
  #   category.update!(owned_by: 'c')
  #   category.update!(owned_by: 'd')

  #   expect(category).to have_a_version_with owned_by: 'b'
  #   expect(category).to have_a_version_with owned_by: 'c'
  # end
end
