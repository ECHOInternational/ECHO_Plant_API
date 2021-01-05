# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Delete Plant Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:plant) { create(:plant) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: DeletePlantInput!){
			deletePlant(input: $input){
				plantId
				errors {
          field
          value
          message
          code
        }
			}
		}
    GRAPHQL
  }

  context 'when user is not authenticated' do
    let(:current_user) { nil }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: plant_id
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 401
    end
  end

  context 'when user is read only' do
    let(:current_user) { build(:user, :readonly) }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: plant_id
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end

  context 'when user is not an admin' do
    let(:current_user) { build(:user, :readwrite) }
    let(:plant) { create(:plant, owned_by: current_user.email, created_by: current_user.email, description: 'a description') }

    context 'when the user does not own the record' do
      let(:plant) { create(:plant, owned_by: 'notme', created_by: 'notme', description: 'a description') }
      it 'raises an error' do
        @plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            plantId: @plant_id
                                          }
                                        })
        expect(result['data']).to be_nil
        expect(result['errors']).to_not be_nil
        expect(result['errors'].count).to eq 1
        expect(result['errors'][0]['extensions']['code']).to eq 403
      end
    end
    context 'when user owns the record' do
      it 'deletes the record' do
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        record_id = plant.id
        expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            plantId: plant_id
                                          }
                                        })
        expect(result).to_not include 'errors'
        expect(result).to include 'data'
        expect(result['data']['deletePlant']).to include 'plantId'
        expect(result['data']['deletePlant']['plantId']).to eq plant_id
        expect { Plant.find record_id }.to raise_error(ActiveRecord::RecordNotFound)
      end
      context 'when there is a related variety' do
        let(:variety) { create(:variety, owned_by: current_user.email, created_by: current_user.email, description: 'a description', plant: plant) }
        it 'returns an error' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          record_id = plant.id
          expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          expect(variety.plant_id).to eq plant.id
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              plantId: plant_id
                                            }
                                          })
          expect(result).to include 'data'
          expect(result['data']['deletePlant']).to include 'plantId'
          expect(result['data']['deletePlant']['plantId']).to be_nil
          expect(result['data']['deletePlant']['errors'][0]).to include 'code'
          expect(result['data']['deletePlant']['errors'][0]['code']).to eq 400
          expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        end
      end
      context 'when there is a related specimen' do
        let(:specimen) { create(:specimen, plant: plant) }
        it 'returns an error' do
          plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
          record_id = plant.id
          expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          expect(specimen.plant_id).to eq plant.id
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              plantId: plant_id
                                            }
                                          })
          expect(result).to include 'data'
          expect(result['data']['deletePlant']).to include 'plantId'
          expect(result['data']['deletePlant']['plantId']).to be_nil
          expect(result['data']['deletePlant']['errors'][0]).to include 'code'
          expect(result['data']['deletePlant']['errors'][0]['code']).to eq 400
          expect { Plant.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
