require 'rails_helper'

RSpec.describe ImageAttribute, type: :model do
  it "is valid with valid attributes" do
  	image_attribute = build(:image_attribute)
  	expect(image_attribute).to be_valid
  end
  it "is not valid without a name" do
  	image_attribute = build(:image_attribute, name: nil)
  	expect(image_attribute).to_not be_valid
  end
end
