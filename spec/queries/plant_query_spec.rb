# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Plant Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads plants by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			plant(id: $id){
				id
        primaryCommonName
        scientificName
        createdAt
        updatedAt
			}
		}
    GRAPHQL

    plant = create(:plant, :public, scientific_name: 'loaded by id')
    plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
    result = PlantApiSchema.execute(query_string, variables: { id: plant_id })

    plant_result = result['data']['plant']
    # Make sure the query worked
    expect(plant_result['id']).to eq plant_id
    expect(plant_result['scientificName']).to eq 'loaded by id'
  end

  it 'does not load plants for which the user is not authorized' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			plant(id: $id){
				id
        primaryCommonName
        scientificName
        createdAt
        updatedAt
			}
		}
    GRAPHQL

    plant = create(:plant, :private, scientific_name: 'Private Plant')
    plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

    result = PlantApiSchema.execute(query_string, variables: { id: plant_id })
    expect(result['data']['plant']).to be nil
    expect(result['errors'].count).to eq 1
    expect(result['errors'][0]['extensions']['code']).to eq 404
  end

  context 'when user is authenticated' do
    it 'loads owned records' do
      current_user = build(:user)

      query_string = <<-GRAPHQL
			query($id: ID!){
				plant(id: $id){
					id
          primaryCommonName
          scientificName
          createdAt
          updatedAt
					ownedBy
				}
			}
      GRAPHQL

      plant = create(:plant, :private, scientific_name: 'Private Plant', owned_by: current_user.email)
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: plant_id })

      plant_result = result['data']['plant']
      # Make sure the query worked
      expect(plant_result['id']).to eq plant_id
      expect(plant_result['scientificName']).to eq 'Private Plant'
      expect(plant_result['ownedBy']).to eq current_user.email
    end
  end

  context 'when user is admin' do
    it 'loads unowned records' do
      current_user = build(:user, :admin)

      query_string = <<-GRAPHQL
			query($id: ID!){
				plant(id: $id){
					id
          primaryCommonName
          scientificName
          createdAt
          updatedAt
					ownedBy
				}
			}
      GRAPHQL

      plant = create(:plant, :private, scientific_name: 'Private Plant', owned_by: 'nottheadmin')
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: plant_id })

      plant_result = result['data']['plant']
      # Make sure the query worked
      expect(plant_result['id']).to eq plant_id
      expect(plant_result['scientificName']).to eq 'Private Plant'
      expect(plant_result['ownedBy']).to eq 'nottheadmin'
    end
  end

  describe 'images attribute' do
    it 'returns a list of scoped image objects' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				plant(id: $id){
					images{
						nodes{
							id
							name
							baseUrl
						}
					}
				}
			}
      GRAPHQL

      plant = create(:plant, :public, scientific_name: 'plant a')
      create(:image, :public, name: 'public_name', imageable: plant)
      create(:image, :private, name: 'private_name', owned_by: 'not me', imageable: plant)
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

      result = PlantApiSchema.execute(query_string, variables: { id: plant_id })
      images_result = result['data']['plant']['images']['nodes']
      images_result_public = images_result.detect { |i| i['name'] == 'public_name' }
      images_result_private = images_result.detect { |i| i['name'] == 'private_name' }
      expect(images_result.count).to eq 1
      expect(images_result_public).to_not be nil
      expect(images_result_private).to be nil
    end
  end
end
