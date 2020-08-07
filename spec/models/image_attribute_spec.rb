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
  it "belongs to many images" do
  	image_a = create(:image, name: "Image_A")
  	image_b = create(:image, name: "Image_B")
  	image_attribute = create(:image_attribute, name:"shared attribute")
  	expect(image_a.image_attributes.count).to eq 0
  	expect(image_b.image_attributes.count).to eq 0
  	expect(image_attribute.images.count).to eq 0
  	image_a.image_attributes << image_attribute
  	expect(image_attribute.images.count).to eq 1
  	image_b.image_attributes << image_attribute
  	expect(image_attribute.images.count).to eq 2
  	expect(image_a.image_attributes.count).to eq 1
  	expect(image_b.image_attributes.count).to eq 1
  end
  it "translates the name attribute" do
    image_attribute = create(:image_attribute, name_en: "name_en")
    image_attribute.name_es = "name_es"
    expect(image_attribute.translations).to have_key(:en)
    expect(image_attribute.translations).to have_key(:es)
    expect(image_attribute.translations[:en]).to have_key(:name)
    expect(image_attribute.translations[:es]).to have_key(:name)
    expect(image_attribute.translations[:en][:name]).to eq('name_en')
    expect(image_attribute.translations[:es][:name]).to eq('name_es')
  end
  describe "when it is destroyed" do
	it "destroys any related image_attributes_images records" do
		image_a = create(:image, name: "Image_A")
		image_attribute = create(:image_attribute, name:"shared attribute")
		image_a.image_attributes << image_attribute
		expect{image_attribute.destroy}.to change{ImageAttributesImage.count}.by(-1)
	end
	it "does not destory related images" do
		image_a = create(:image, name: "Image_A")
		image_attribute = create(:image_attribute, name:"shared attribute")
		image_a.image_attributes << image_attribute
		expect{image_attribute.destroy}.to_not change{Image.count}
	end
  end
end
