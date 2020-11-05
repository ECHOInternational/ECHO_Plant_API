# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Variety Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: CreateVarietyInput!){
			createVariety(input: $input){
        errors{
          field
          value
          message
          code
        }
				variety{
          id
          name
          plant{
            id
            uuid
          }
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
    let(:plant) { create(:plant) }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: {
          input: {
            plantId: plant_id,
            name: 'newly created record',
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
    let(:plant) { create(:plant) }
    it 'returns an error when called' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: {
          input: {
            plantId: plant_id,
            name: 'newly created record',
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
      @plant = create(:plant)
      @plant_id = PlantApiSchema.id_from_object(@plant, Plant, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           plantId: @plant_id,
                                           name: 'newly created record',
                                           description: 'with an attached description',
                                           language: 'en'
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'creates a record' do
      variety_result = @result['data']['createVariety']['variety']
      expect(variety_result['name']).to eq 'newly created record'
      expect(variety_result['description']).to eq 'with an attached description'

      created_variety = Variety.find variety_result['uuid']
      expect(created_variety).to_not be nil
      expect(created_variety.name).to eq 'newly created record'
    end

    it 'is related to the specified plant' do
      plant_result = @result['data']['createVariety']['variety']['plant']
      variety_result = @result['data']['createVariety']['variety']
      created_variety = Variety.find variety_result['uuid']
      expect(plant_result['id']).to eq @plant_id

      related_plant = Plant.find plant_result['uuid']
      expect(related_plant).not_to be nil
      expect(related_plant.varieties).to include created_variety
    end

    it 'sets ownership to the current user' do
      variety_result = @result['data']['createVariety']['variety']
      expect(variety_result['ownedBy']).to eq current_user.email
    end
    it 'sets creator to the current user' do
      variety_result = @result['data']['createVariety']['variety']
      expect(variety_result['createdBy']).to eq current_user.email
    end
  end
  describe 'parameters' do
    let(:current_user) { build(:user, :readwrite) }
    let(:plant) { create(:plant) }
    describe 'language' do
      it 'sets the language' do
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               plantId: plant_id,
                                               name: 'newly created record in spanish',
                                               description: 'with an attached description in spanish',
                                               language: 'es'
                                             }
                                           })
        variety_es_result = es_result['data']['createVariety']['variety']
        created_variety_es = Variety.find variety_es_result['uuid']

        expect(created_variety_es.translations).to include 'es'
        expect(created_variety_es.translations).to_not include 'en'
      end
    end
    describe 'visibility' do
      it 'sets the visibility' do
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            plantId: plant_id,
                                            name: 'a public record',
                                            visibility: 'PUBLIC'
                                          }
                                        })
        variety_result = result['data']['createVariety']['variety']
        created_variety = Variety.find variety_result['uuid']
        expect(created_variety.visibility_public?).to be true
        expect(created_variety.visibility_private?).to be false
      end
    end
    it 'returns errors when the input is invalid' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: plant_id,
                                          name: '',
                                          description: 'A description'
                                        }
                                      })
      error_result = result['data']['createVariety']['errors']
      expect(error_result[0]['field']).to eq 'name'
      expect(error_result[0]['message']).to eq "name can't be blank"
      expect(error_result[0]['code']).to eq 400
    end
    it "returns an error when the plant can't be found" do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          plantId: 'foo',
                                          name: '',
                                          description: 'A description'
                                        }
                                      })
      expect(result['data']).to be_nil
      expect(result['errors']).to_not be_nil
      expect(result['errors'].count).to eq 1
      expect(result['errors'][0]['extensions']['code']).to eq 404
    end
  end
end
