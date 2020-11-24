# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Specimen, type: :model do
  it 'is valid with valid attributes' do
    specimen = build(:specimen)
    expect(specimen).to be_valid
  end
  it 'is not valid without a name' do
    specimen = build(:specimen, name: nil)
    expect(specimen).to_not be_valid
  end
  it 'is not valid without a creator' do
    specimen = build(:specimen, created_by: nil)
    expect(specimen).to_not be_valid
  end
  it 'is not valid without an owner' do
    specimen = build(:specimen, owned_by: nil)
    expect(specimen).to_not be_valid
  end
  it 'is not valid without a plant' do
    specimen = build(:specimen, plant: nil)
    expect(specimen).to_not be_valid
  end
  it "has a default visibility of 'private'" do
    specimen = build(:specimen)
    expect(specimen).to be_valid
    expect(specimen.visibility).to eq('private')
  end

  it 'has a default evaluated_at of nil' do
    specimen = build(:specimen)
    expect(specimen).to be_valid
    expect(specimen.evaluated_at).to be nil
  end

  it 'can set visibility' do
    specimen = build(:specimen, :public)
    expect(specimen).to be_valid
    expect(specimen.visibility).to eq('public')
  end

  it 'is destroys all related images when it is destroyed' do
    specimen = create(:specimen)
    create(:image, imageable: specimen)
    expect { specimen.destroy }.to change { Image.count }.by(-1)
  end

  it 'is versioned' do
    is_expected.to be_versioned
    specimen = build(:specimen)
    expect(specimen).to respond_to(:versions)
  end

  it 'belongs to a plant' do
    plant = create(:plant)
    specimen = create(:specimen, plant: plant)
    expect(specimen.plant_id).to eq plant.id
    expect(plant.specimens.first).to eq specimen
  end

  it 'can belong to a variety' do
    variety = create(:variety)
    specimen = create(:specimen, plant: variety.plant, variety: variety)
    expect(specimen.variety_id).to eq variety.id
    expect(variety.specimens.first).to eq specimen
  end

  describe 'when it is destroyed' do
    it 'does not destroy related plants' do
      plant = create(:plant)
      specimen = create(:specimen, plant: plant)
      expect { specimen.destroy }.to_not change { Plant.count }
    end
    it 'does not destroy related varieties' do
      variety = create(:variety)
      specimen = create(:specimen, plant: variety.plant, variety: variety)
      expect { specimen.destroy }.to_not change { Variety.count }
    end
  end
end
