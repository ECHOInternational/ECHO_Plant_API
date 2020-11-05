# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Delete Variety Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:variety) { create(:variety) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: DeleteVarietyInput!){
			deleteVariety(input: $input){
				varietyId
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
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          varietyId: variety_id
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
                                          varietyId: variety_id
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
                                            varietyId: @variety_id
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
      end
      it 'deletes the record' do
        record_id = variety.id
        expect { Variety.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            varietyId: @variety_id
                                          }
                                        })
        expect(result).to_not include 'errors'
        expect(result).to include 'data'
        expect(result['data']['deleteVariety']).to include 'varietyId'
        expect(result['data']['deleteVariety']['varietyId']).to eq @variety_id
        expect { Variety.find record_id }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
