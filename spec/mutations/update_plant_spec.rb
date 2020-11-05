# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Plant Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:plant) { create(:plant) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdatePlantInput!){
			updatePlant(input: $input){
        errors{
          field
          value
          message
          code
        }
				plant{
					id
          primaryCommonName
          scientificName
          familyNames
					uuid
					description
					ownedBy
					createdBy
				}
			}
		}
    GRAPHQL
  }

  before :each do
    Mobility.locale = nil
  end

  context 'when user is not authenticated' do
    let(:current_user) { nil }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: plant_id,
                                          primaryCommonName: 'newly created record',
                                          description: 'with an attached description',
                                          language: 'en'
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
                                          plantId: plant_id,
                                          primaryCommonName: 'newly created record',
                                          description: 'with an attached description',
                                          language: 'en'
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
                                            plantId: @plant_id,
                                            primaryCommonName: 'updated record to this',
                                            description: 'and updated the description',
                                            language: 'en'
                                          }
                                        })
        expect(result['data']).to be_nil
        expect(result['errors']).to_not be_nil
        expect(result['errors'].count).to eq 1
        expect(result['errors'][0]['extensions']['code']).to eq 403
      end
    end
    context 'when user owns the record' do
      before :each do
        @plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                           input: {
                                             plantId: @plant_id,
                                             primaryCommonName: 'updated record to this',
                                             description: 'and updated the description',
                                             familyNames: 'new family names',
                                             scientificName: 'new scientific name',
                                             language: 'en'
                                           }
                                         })
      end
      it 'completes successfully' do
        expect(@result).to_not include 'errors'
        expect(@result).to include 'data'
      end

      it 'updates a record' do
        plant_result = @result['data']['updatePlant']['plant']
        expect(plant_result['primaryCommonName']).to eq 'updated record to this'
        expect(plant_result['description']).to eq 'and updated the description'
        expect(plant_result['familyNames']).to eq 'new family names'
        expect(plant_result['scientificName']).to eq 'new scientific name'
      end

      it 'can update records in the speficied language' do
        plant_en_result = @result['data']['updatePlant']['plant']
        created_plant_en = Plant.find plant_en_result['uuid']
        expect(created_plant_en.translations).to_not include 'es'
        expect(created_plant_en.translations).to include 'en'

        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               plantId: @plant_id,
                                               primaryCommonName: 'added this in spanish',
                                               description: 'with an attached description in spanish',
                                               language: 'es'
                                             }
                                           })
        plant_es_result = es_result['data']['updatePlant']['plant']
        created_plant_es = Plant.find plant_es_result['uuid']
        expect(created_plant_es.primary_common_name_for_locale('en')).to eq 'updated record to this'
        expect(created_plant_es.primary_common_name_for_locale('es')).to eq 'added this in spanish'
        expect(created_plant_es.translations).to include 'en'
        expect(created_plant_es.translations).to include 'es'
      end

      it 'can update the visibility status' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            plantId: @plant_id,
                                            visibility: 'PUBLIC'
                                          }
                                        })
        plant_result = result['data']['updatePlant']['plant']
        created_plant = Plant.find plant_result['uuid']

        expect(created_plant.visibility_public?).to be true
        expect(created_plant.visibility_private?).to be false
      end
    end
  end
end
