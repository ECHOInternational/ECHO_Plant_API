# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Location Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:location) { create(:location) }
  let(:query_string) {
    <<-GRAPHQL
      mutation($input: UpdateLocationInput!){
        updateLocation(input: $input){
          location{
            id
            name
            latitude
            longitude
          }
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
                                          locationId: location_id,
                                          name: 'new name'
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
                                          locationId: location_id,
                                          name: 'new name'
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
    let(:location) { create(:location, owned_by: current_user.email, created_by: current_user.email) }

    context 'when the user does not own the record' do
      let(:location) { create(:location, owned_by: 'notme', created_by: 'notme') }
      it 'raises an error' do
        location_id = PlantApiSchema.id_from_object(location, Location, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            locationId: location_id,
                                            name: 'new name'
                                          }
                                        })
        expect(result['data']).to be_nil
        expect(result['errors']).to_not be_nil
        expect(result['errors'].count).to eq 1
        expect(result['errors'][0]['extensions']['code']).to eq 403
      end
    end

    context 'when user owns the record' do
      context 'clearing both latitude and longitude via explicit nulls' do
        it 'sets latlng to nil and returns no errors' do
          location_id = PlantApiSchema.id_from_object(location, Location, {})
          expect(location.latlng).not_to be_nil
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              locationId: location_id,
                                              latitude: nil,
                                              longitude: nil
                                            }
                                          })
          expect(result['data']).to_not be_nil
          expect(result['data']['updateLocation']['errors']).to be_empty
          expect(location.reload.latlng).to be_nil
        end
      end

      context 'clearing only latitude (one-sided nil)' do
        it 'returns a 400 payload error and does not save' do
          location_id = PlantApiSchema.id_from_object(location, Location, {})
          original_latlng = location.latlng
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              locationId: location_id,
                                              latitude: nil
                                            }
                                          })
          expect(result['data']).to_not be_nil
          errors = result['data']['updateLocation']['errors']
          expect(errors.count).to eq 1
          expect(errors[0]['field']).to eq 'latitude'
          expect(errors[0]['code']).to eq 400
          expect(location.reload.latlng).to eq original_latlng
        end
      end

      context 'clearing only longitude (one-sided nil)' do
        it 'returns a 400 payload error and does not save' do
          location_id = PlantApiSchema.id_from_object(location, Location, {})
          original_latlng = location.latlng
          result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                            input: {
                                              locationId: location_id,
                                              longitude: nil
                                            }
                                          })
          expect(result['data']).to_not be_nil
          errors = result['data']['updateLocation']['errors']
          expect(errors.count).to eq 1
          expect(errors[0]['field']).to eq 'longitude'
          expect(errors[0]['code']).to eq 400
          expect(location.reload.latlng).to eq original_latlng
        end
      end
    end
  end
end
