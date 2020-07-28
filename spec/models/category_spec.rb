require 'rails_helper'

RSpec.describe Category, type: :model do
  it "is valid with valid attributes" do
  	category = build(:category)
  	expect(category).to be_valid
  end
  it "is not valid without a name" do
  	category = build(:category, name: nil)
  	expect(category).to_not be_valid
  end
  it "is not valid without a creator" do
  	category = build(:category, created_by: nil)
  	expect(category).to_not be_valid
  end
  it "is not valid without an owner" do
  	category = build(:category, owned_by: nil)
  	expect(category).to_not be_valid
  end
  it "has a default visibility of 'private'" do
  	category = build(:category)
  	expect(category).to be_valid
  	expect(category.visibility).to eq('private')
  end
  it "can set visibility" do
    category = build(:category, :public)
    expect(category).to be_valid
    expect(category.visibility).to eq('public')
  end
  it "translates the name attribute" do
    category = create(:category, name_en: "name_en")
    category.name_es = "name_es"
    expect(category.translations).to have_key(:en)
    expect(category.translations).to have_key(:es)
    expect(category.translations[:en]).to have_key(:name)
    expect(category.translations[:es]).to have_key(:name)
    expect(category.translations[:en][:name]).to eq('name_en')
    expect(category.translations[:es][:name]).to eq('name_es')
  end
  it "is versioned" do
    is_expected.to be_versioned
    category = build(:category)
    expect(category).to respond_to(:versions)
  end

  with_versioning do
    it 'can track changes' do
      category = create(:category, owned_by: 'a')
      category.update!(owned_by: 'b')
      category.update!(owned_by: 'c')
      category.update!(owned_by: 'd')
      expect(category).to have_a_version_with owned_by: 'b'
      expect(category).to have_a_version_with owned_by: 'c'
    end
  end

  
  
end
