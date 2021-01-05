# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Delete Location Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:location) { create(:location) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: DeleteLocationInput!){
			deleteLocation(input: $input){
				locationId
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
      location_id = PlantApiSchema.id_from_object(location, Location, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          locationId: location_id
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
      location_id = PlantApiSchema.id_from_object(location, Location, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          locationId: location_id
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
    let(:location) { create(:location, owned_by: current_user.email, created_by: current_user.email, name: 'a name') }

    context 'when the user does not own the record' do
      let(:location) { create(:location, owned_by: 'notme', created_by: 'notme', name: 'a name') }
      it 'raises an error' do
        @location_id = PlantApiSchema.id_from_object(location, Location, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            locationId: @location_id
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
        location_id = PlantApiSchema.id_from_object(location, Location, {})
        record_id = location.id
        expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            locationId: location_id
                                          }
                                        })
        expect(result).to_not include 'errors'
        expect(result).to include 'data'
        expect(result['data']['deleteLocation']).to include 'locationId'
        expect(result['data']['deleteLocation']['locationId']).to eq location_id
        expect { Location.find record_id }.to raise_error(ActiveRecord::RecordNotFound)
      end
      context 'when there is a related lifecycle event' do
        let(:lce) { create(:planting_event, location: location) }
        it 'returns an error' do
          location_id = PlantApiSchema.id_from_object(location, Location, {})
          record_id = location.id
          expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          expect(lce.location_id).to eq location.id
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              locationId: location_id
                                            }
                                          })
          expect(result).to include 'data'
          expect(result['data']['deleteLocation']).to include 'locationId'
          expect(result['data']['deleteLocation']['locationId']).to be_nil
          expect(result['data']['deleteLocation']['errors'][0]).to include 'code'
          expect(result['data']['deleteLocation']['errors'][0]['code']).to eq 400
          expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
