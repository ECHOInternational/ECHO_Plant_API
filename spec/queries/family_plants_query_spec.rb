# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'family plants', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let!(:public_plant) { create(:plant, :public, family: family, scientific_name: 'Vigna unguiculata') }
  let!(:private_plant) { create(:plant, :private, family: family, scientific_name: 'Secret bean') }

  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  def execute(query, user)
    PlantApiSchema.execute(query, variables: { 'id' => global_id },
                                  context: { current_user: user })
  end

  it 'lists only public plants for an anonymous caller' do
    result = execute(<<~GQL, nil)
      query($id: ID!) { family(id: $id) { plants(first: 10) { totalCount nodes { scientificName } } } }
    GQL
    names = result.dig('data', 'family', 'plants', 'nodes').map { |n| n['scientificName'] }
    expect(names).to eq(['Vigna unguiculata'])
    expect(result.dig('data', 'family', 'plants', 'totalCount')).to eq(1)
  end

  it 'exposes the family from the plant side' do
    plant_id = PlantApiSchema.id_from_object(public_plant, Plant, {})
    result = PlantApiSchema.execute(<<~GQL, variables: { 'id' => plant_id }, context: { current_user: nil })
      query($id: ID!) { plant(id: $id) { family { name } familyNames } }
    GQL
    expect(result.dig('data', 'plant', 'family', 'name')).to eq('Fabaceae')
  end

  it 'returns a null family when the plant has none' do
    orphan = create(:plant, :public, family: nil)
    plant_id = PlantApiSchema.id_from_object(orphan, Plant, {})
    result = PlantApiSchema.execute(<<~GQL, variables: { 'id' => plant_id }, context: { current_user: nil })
      query($id: ID!) { plant(id: $id) { family { name } } }
    GQL
    expect(result.dig('data', 'plant', 'family')).to be_nil
  end
end
