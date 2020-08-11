require 'rails_helper'

RSpec.describe ImageAttributesImage, type: :model do
  it 'is valid with valid attributes' do
    join_record = build(:image_attributes_image)
    expect(join_record).to be_valid
  end
  it 'is not valid without an image' do
    join_record = build(:image_attributes_image, image: nil)
    expect(join_record).to_not be_valid
  end
  it 'is not valid without an image_attribute' do
    join_record = build(:image_attributes_image, image_attribute: nil)
    expect(join_record).to_not be_valid
  end
  it 'enforces uniqueness constraint' do
    image = create(:image)
    image_attribute = create(:image_attribute)
    expect { image.image_attributes << image_attribute }.to_not raise_error
    expect { image.image_attributes << image_attribute }.to raise_error
  end
end
