require 'rails_helper'

RSpec.describe Location, type: :model, focus: true do
  it 'is valid with valid attributes' do
    location = build(:location)
    expect(location).to be_valid
  end
  it 'is not valid without a name' do
    location = build(:location, name: nil)
    expect(location).to_not be_valid
  end
  it 'is not valid without a creator' do
    location = build(:location, created_by: nil)
    expect(location).to_not be_valid
  end
  it 'is not valid without an owner' do
    location = build(:location, owned_by: nil)
    expect(location).to_not be_valid
  end
  it "has a default visibility of 'private'" do
    location = build(:location)
    expect(location).to be_valid
    expect(location.visibility).to eq('private')
  end
  it 'can set visibility' do
    location = build(:location, :public)
    expect(location).to be_valid
    expect(location.visibility).to eq('public')
  end

  it 'is destroys all related images when it is destroyed' do
    location = create(:location)
    create(:image, imageable: location)
    expect { location.destroy }.to change { Image.count }.by(-1)
  end

  it 'is versioned' do
    is_expected.to be_versioned
    location = build(:location)
    expect(location).to respond_to(:versions)
  end

  describe 'soil quality enum' do
    it 'can set soil_quality by symbol' do
      location = create(:location, soil_quality: :poor)
      expect(location.soil_quality).to eq 'poor'
    end
    it 'can query by soil_quality' do
      location = create(:location, soil_quality: :good)
      expect(Location.soil_quality_good.first).to eq location
      expect(Location.soil_quality_poor.first).to be_nil
    end
  end

  describe 'latlng' do
    it 'requires both a latitude and a longitude' do
      location = build(:location, latlng: [1.25])
      expect { location.save! }.to raise_error
      location = build(:location, latlng: [1.25, 1.55])
      expect { location.save! }.to_not raise_error
    end
  end

  describe 'latitude' do
    let(:location) { build(:location, latlng: [11, 12]) }
    it 'can set the latitude using the latitude setter' do
      location.latitude = 44
      expect(location.latlng.x).to eq 44
    end
    it 'can read the latitude using the latitude getter' do
      expect(location.latitude).to eq 11
    end
  end

  describe 'longitude' do
    let(:location) { build(:location, latlng: [21, 31]) }
    it 'can set the longitude using the longitude setter' do
      location.longitude = 55
      expect(location.latlng.y).to eq 55
    end
    it 'can read the longitude using the longitude getter' do
      expect(location.longitude).to eq 31
    end
  end


  # it 'belongs to a plant' do
  #   plant = create(:plant)
  #   location = create(:location, plant: plant)
  #   expect(location.plant_id).to eq plant.id
  #   expect(plant.locations.first).to eq location
  # end

  # it 'can belong to a variety' do
  #   variety = create(:variety)
  #   location = create(:location, plant: variety.plant, variety: variety)
  #   expect(location.variety_id).to eq variety.id
  #   expect(variety.locations.first).to eq location
  # end

  # describe 'when it is destroyed' do
  #   it 'does not destroy related plants' do
  #     plant = create(:plant)
  #     location = create(:location, plant: plant)
  #     expect { location.destroy }.to_not change { Plant.count }
  #   end
  #   it 'does not destroy related varieties' do
  #     variety = create(:variety)
  #     location = create(:location, plant: variety.plant, variety: variety)
  #     expect { location.destroy }.to_not change { Variety.count }
  #   end
  # end
end
