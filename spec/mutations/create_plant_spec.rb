# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Plant Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: CreatePlantInput!){
			createPlant(input: $input){
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
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: {
          input: {
            primaryCommonName: 'newly created record',
            description: 'with an attached description',
            language: 'en'
          }
        }
      )
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 401
    end
  end

  context 'when user is read only' do
    let(:current_user) { build(:user, :readonly) }
    it 'returns an error when called' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: {
          input: {
            primaryCommonName: 'newly created record',
            description: 'with an attached description',
            language: 'en'
          }
        }
      )
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end

  context 'when user is authenticated' do
    let(:current_user) { build(:user, :readwrite) }
    before :each do
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           primaryCommonName: 'newly created record',
                                           description: 'with an attached description',
                                           scientificName: 'and a scientific name',
                                           familyNames: 'and family names',
                                           language: 'en'
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'creates a record' do
      plant_result = @result['data']['createPlant']['plant']
      expect(plant_result['primaryCommonName']).to eq 'newly created record'
      expect(plant_result['description']).to eq 'with an attached description'
      expect(plant_result['scientificName']).to eq 'and a scientific name'
      expect(plant_result['familyNames']).to eq 'and family names'

      created_plant = Plant.find plant_result['uuid']
      expect(created_plant).to_not be nil
      expect(created_plant.primary_common_name).to eq 'newly created record'
    end

    it 'sets ownership to the current user' do
      plant_result = @result['data']['createPlant']['plant']
      expect(plant_result['ownedBy']).to eq current_user.email
    end
    it 'sets creator to the current user' do
      plant_result = @result['data']['createPlant']['plant']
      expect(plant_result['createdBy']).to eq current_user.email
    end
  end
  describe 'parameters' do
    let(:current_user) { build(:user, :readwrite) }
    describe 'language' do
      it 'sets the language' do
        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               primaryCommonName: 'newly created record in spanish',
                                               description: 'with an attached description in spanish',
                                               language: 'es'
                                             }
                                           })
        plant_es_result = es_result['data']['createPlant']['plant']
        created_plant_es = Plant.find plant_es_result['uuid']

        expect(created_plant_es.translations).to include 'es'
        expect(created_plant_es.translations).to_not include 'en'
      end
    end
    describe 'visibility' do
      it 'sets the visibility' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            primaryCommonName: 'a public record',
                                            visibility: 'PUBLIC'
                                          }
                                        })
        plant_result = result['data']['createPlant']['plant']
        created_plant = Plant.find plant_result['uuid']
        expect(created_plant.visibility_public?).to be true
        expect(created_plant.visibility_private?).to be false
      end
    end
    it 'returns errors when the input is invalid' do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          primaryCommonName: '',
                                          description: 'A description'
                                        }
                                      })
      error_result = result['data']['createPlant']['errors']
      expect(error_result[0]['field']).to eq 'common_names'
      expect(error_result[0]['message']).to eq 'common_names is invalid'
      expect(error_result[0]['code']).to eq 400
    end
  end
end
