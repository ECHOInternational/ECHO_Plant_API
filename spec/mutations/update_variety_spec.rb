# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Variety Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:variety) { create(:variety) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdateVarietyInput!){
			updateVariety(input: $input){
        errors{
          field
          value
          message
          code
        }
				variety{
          id
          plant{
            id
            uuid
          }
					name
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
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          varietyId: variety_id,
                                          name: 'newly created record',
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
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          varietyId: variety_id,
                                          name: 'newly created record',
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
    let(:variety) { create(:variety, owned_by: current_user.email, created_by: current_user.email, name: 'a name', description: 'a description') }

    context 'when the user does not own the record' do
      let(:variety) { create(:variety, owned_by: 'notme', created_by: 'notme', name: 'a name', description: 'a description') }
      it 'raises an error' do
        @variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id,
                                            name: 'updated record to this',
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
        @variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
        @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                           input: {
                                             varietyId: @variety_id,
                                             name: 'updated record to this',
                                             description: 'and updated the description',
                                             language: 'en'
                                           }
                                         })
      end
      it 'completes successfully' do
        expect(@result).to_not include 'errors'
        expect(@result).to include 'data'
      end

      it 'updates a record' do
        variety_result = @result['data']['updateVariety']['variety']
        expect(variety_result['name']).to eq 'updated record to this'
        expect(variety_result['description']).to eq 'and updated the description'
      end

      it 'can update records in the speficied language' do
        variety_en_result = @result['data']['updateVariety']['variety']
        created_variety_en = Variety.find variety_en_result['uuid']
        expect(created_variety_en.translations).to_not include 'es'
        expect(created_variety_en.translations).to include 'en'

        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               varietyId: @variety_id,
                                               description: 'with an attached description in spanish',
                                               language: 'es'
                                             }
                                           })
        variety_es_result = es_result['data']['updateVariety']['variety']
        created_variety_es = Variety.find variety_es_result['uuid']
        expect(created_variety_es.translations).to include 'en'
        expect(created_variety_es.translations).to include 'es'
      end

      it 'can update the visibility status' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id,
                                            visibility: 'PUBLIC'
                                          }
                                        })
        variety_result = result['data']['updateVariety']['variety']
        created_variety = Variety.find variety_result['uuid']

        expect(created_variety.visibility_public?).to be true
        expect(created_variety.visibility_private?).to be false
      end

      it 'can update the plant to which it is related' do
        plant = create(:plant)
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id,
                                            plantId: plant_id
                                          }
                                        })
        variety_result = result['data']['updateVariety']['variety']
        created_variety = Variety.find variety_result['uuid']

        expect(variety_result['plant']['id']).to eq plant_id
        expect(plant.varieties).to include created_variety
      end

      it 'returns errors when the input is invalid' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id,
                                            name: nil
                                          }
                                        })
        error_result = result['data']['updateVariety']['errors']
        expect(error_result[0]['field']).to eq 'name'
        expect(error_result[0]['message']).to eq "name can't be blank"
        expect(error_result[0]['code']).to eq 400
      end

      it 'returns errors when the specified plant cannot be found' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id,
                                            plantId: 'foo'
                                          }
                                        })
        expect(result['data']).to be_nil
        expect(result['errors']).to_not be_nil
        expect(result['errors'].count).to eq 1
        expect(result['errors'][0]['extensions']['code']).to eq 404
      end
    end
  end
end
