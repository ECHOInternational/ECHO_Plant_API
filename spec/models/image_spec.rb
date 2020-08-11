# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Image, type: :model do
  it 'is valid with valid attributes' do
    image = build(:image)
    expect(image).to be_valid
  end
  it 'is not valid without an id' do
    image = build(:image, id: nil)
    expect(image).to_not be_valid
  end
  it 'is not valid without a name' do
    image = build(:image, name: nil)
    expect(image).to_not be_valid
  end
  it 'is not valid without a creator' do
    image = build(:image, created_by: nil)
    expect(image).to_not be_valid
  end
  it 'is not valid without an owner' do
    image = build(:image, owned_by: nil)
    expect(image).to_not be_valid
  end

  it 'is not valid without an imageable object' do
    image = build(:image, imageable: nil)
    expect(image).to_not be_valid
  end

  it 'is not valid if the ID is already taken' do
    image = create(:image)
    expect { create(:image, id: image.id) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'cannot change s3_bucket after creation' do
    image = create(:image)
    expect { image.s3_bucket = 'new bucket' }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'cannot change s3_key after creation' do
    image = create(:image)
    expect { image.s3_key = 'new key' }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'generates a base_url after creation' do
    image = create(:image, s3_key: 'find_this')
    image.reload
    expect(image.base_url).to end_with('find_this')
  end

  it "has a default visibility of 'private'" do
    image = build(:image)
    expect(image).to be_valid
    expect(image.visibility).to eq('private')
  end
  it 'can set visibility' do
    image = build(:image, :public)
    expect(image).to be_valid
    expect(image.visibility).to eq('public')
  end

  it 'translates the name attribute' do
    image = create(:image, name_en: 'name_en')
    image.name_es = 'name_es'
    expect(image.translations).to have_key(:en)
    expect(image.translations).to have_key(:es)
    expect(image.translations[:en]).to have_key(:name)
    expect(image.translations[:es]).to have_key(:name)
    expect(image.translations[:en][:name]).to eq('name_en')
    expect(image.translations[:es][:name]).to eq('name_es')
  end

  it 'has many image_attributes' do
    image = create(:image)
    image_attribute_a = create(:image_attribute, name: 'Image Attribute A')
    image_attribute_b = create(:image_attribute, name: 'Image Attribute B')
    expect { image.image_attributes << image_attribute_a }.to change { image.image_attributes.count }.by(1)
    expect { image.image_attributes << image_attribute_b }.to change { image.image_attributes.count }.by(1)
  end
  describe 'when it is destroyed' do
    it 'destroys any related image_attributes_images records' do
      image = create(:image)
      image_attribute = create(:image_attribute)
      image.image_attributes << image_attribute
      expect { image.destroy }.to change { ImageAttributesImage.count }.by(-1)
    end
    it 'does not destory related image_attributes' do
      image = create(:image)
      image_attribute = create(:image_attribute)
      image.image_attributes << image_attribute
      expect { image.destroy }.to_not change { ImageAttribute.count }
    end
  end

  it 'translates the name attribute' do
    image = create(:image, name_en: 'name_en')
    image.name_es = 'name_es'
    expect(image.translations).to have_key(:en)
    expect(image.translations).to have_key(:es)
    expect(image.translations[:en]).to have_key(:name)
    expect(image.translations[:es]).to have_key(:name)
    expect(image.translations[:en][:name]).to eq('name_en')
    expect(image.translations[:es][:name]).to eq('name_es')
  end

  it 'is versioned' do
    is_expected.to be_versioned
    image = build(:image)
    expect(image).to respond_to(:versions)
  end
  # it 'can track changes', versioning: true do
  #   expect(PaperTrail).to be_enabled
  #   image = create(:image, owned_by: 'a')
  #   image.update!(owned_by: 'b')
  #   image.update!(owned_by: 'c')
  #   image.update!(owned_by: 'd')

  #   expect(image).to have_a_version_with owned_by: 'b'
  #   expect(image).to have_a_version_with owned_by: 'c'
  # end

  it 'can be created with an array of image attributes' do
    attr_a = create(:image_attribute)
    attr_b = create(:image_attribute)
    category = create(:category)
    image = Image.new(
      id: SecureRandom.uuid,
      imageable: category,
      name: 'A name',
      owned_by: 'me',
      created_by: 'me',
      s3_bucket: 'bucket',
      s3_key: 'key',
      image_attributes: [attr_a, attr_b]
    )
    expect(image).to be_valid
    expect(image.image_attributes).to include(attr_a)
    expect(image.image_attributes).to include(attr_b)
  end
end
