# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create Category Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: CreateCategoryInput!){
			createCategory(input: $input){
        errors{
          field
          value
          message
          code
        }
				category{
					id
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
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: {
          input: {
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
    it 'returns an error when called' do
      result = PlantApiSchema.execute(
        query_string,
        context: { current_user: current_user },
        variables: {
          input: {
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
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
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
      category_result = @result['data']['createCategory']['category']
      expect(category_result['name']).to eq 'newly created record'
      expect(category_result['description']).to eq 'with an attached description'

      created_category = Category.find category_result['uuid']
      expect(created_category).to_not be nil
      expect(created_category.name).to eq 'newly created record'
    end

    it 'sets ownership to the current user' do
      category_result = @result['data']['createCategory']['category']
      expect(category_result['ownedBy']).to eq current_user.email
    end
    it 'sets creator to the current user' do
      category_result = @result['data']['createCategory']['category']
      expect(category_result['createdBy']).to eq current_user.email
    end
  end
  describe 'parameters' do
    let(:current_user) { build(:user, :readwrite) }
    describe 'language' do
      it 'sets the language' do
        es_result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                             input: {
                                               name: 'newly created record in spanish',
                                               description: 'with an attached description in spanish',
                                               language: 'es'
                                             }
                                           })
        category_es_result = es_result['data']['createCategory']['category']
        created_category_es = Category.find category_es_result['uuid']

        expect(created_category_es.translations).to include 'es'
        expect(created_category_es.translations).to_not include 'en'
      end
    end
    describe 'visibility' do
      it 'sets the visibility' do
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            name: 'a public record',
                                            visibility: 'PUBLIC'
                                          }
                                        })
        category_result = result['data']['createCategory']['category']
        created_category = Category.find category_result['uuid']
        expect(created_category.visibility_public?).to be true
        expect(created_category.visibility_private?).to be false
      end
    end
    it 'returns errors when the input is invalid' do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          name: '',
                                          description: 'A description'
                                        }
                                      })
      error_result = result['data']['createCategory']['errors']
      expect(error_result[0]['field']).to eq 'name'
      expect(error_result[0]['message']).to eq "name can't be blank"
      expect(error_result[0]['code']).to eq 400
    end
  end
end
