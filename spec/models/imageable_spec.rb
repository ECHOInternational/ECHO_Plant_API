require 'rails_helper'

RSpec.describe "Imageable Objects" do
  let(:imageable) { create(:category) }
  it "responds to images" do
    expect(imageable).to respond_to(:images)
    expect(imageable.images).to be_a(ActiveRecord::Associations::CollectionProxy)
  end
  it "it creates new images with the correct relationship" do
    image = imageable.images.new
    expect(image.imageable_type).to eq imageable.class.to_s
    expect(image.imageable_id).to eq imageable.id
  end
end
