# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Soft Delete Location Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:location) { create(:location) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: SoftDeleteLocationInput!){
			softDeleteLocation(input: $input){
				location {
          id
          visibility
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
      context 'with no related records' do
        it 'soft deletes the record' do
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
          expect(result['data']['softDeleteLocation']).to include 'location'
          expect(result['data']['softDeleteLocation']['location']['id']).to eq location_id
          expect(result['data']['softDeleteLocation']['location']['visibility']).to eq "DELETED"
          expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          location.reload
          expect(location.visibility).to eq 'deleted'
        end
      end
      context 'when there is a related life cycle event' do
        context 'and the life cycle event is not soft-deleted' do
          let(:life_cycle_event) { create(:planting_event, location: location) }
          context 'and the life cycle event parent is not soft-deleted' do
            let(:specimen) {create(:specimen, visibility: :private)}
            let(:life_cycle_event) { create(:planting_event, location: location, specimen: specimen) }
            it 'returns an error' do
              location_id = PlantApiSchema.id_from_object(location, Location, {})
              record_id = location.id
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(life_cycle_event.location_id).to eq location.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  locationId: location_id
                                                }
                                              })
              expect(result).to include 'data'
              expect(result['data']['softDeleteLocation']).to include 'location'
              expect(result['data']['softDeleteLocation']['location']['visibility']).to_not eq "DELETED"
              expect(result['data']['softDeleteLocation']['errors'][0]).to include 'code'
              expect(result['data']['softDeleteLocation']['errors'][0]['code']).to eq 400
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            end
          end
          context 'and the life cycle event parent is soft deleted' do
            let(:specimen) {create(:specimen, visibility: :deleted)}
            let(:life_cycle_event) { create(:planting_event, location: location, specimen: specimen) }
            it 'soft deletes the record' do
              location_id = PlantApiSchema.id_from_object(location, Location, {})
              record_id = location.id
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(life_cycle_event.location_id).to eq location.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  locationId: location_id,
                                                }
                                              })
              expect(result).to_not include 'errors'
              expect(result).to include 'data'
              expect(result['data']['softDeleteLocation']).to include 'location'
              expect(result['data']['softDeleteLocation']['location']['id']).to eq location_id
              expect(result['data']['softDeleteLocation']['location']['visibility']).to eq "DELETED"
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              location.reload
              expect(location.visibility).to eq 'deleted'
            end
          end
          context 'without force parameter' do
            it 'returns an error' do
              location_id = PlantApiSchema.id_from_object(location, Location, {})
              record_id = location.id
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(life_cycle_event.location_id).to eq location.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  locationId: location_id
                                                }
                                              })
              expect(result).to include 'data'
              expect(result['data']['softDeleteLocation']).to include 'location'
              expect(result['data']['softDeleteLocation']['location']['visibility']).to_not eq "DELETED"
              expect(result['data']['softDeleteLocation']['errors'][0]).to include 'code'
              expect(result['data']['softDeleteLocation']['errors'][0]['code']).to eq 400
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            end
          end
          context 'when force parameter is true' do
            it 'soft deletes the record' do
              location_id = PlantApiSchema.id_from_object(location, Location, {})
              record_id = location.id
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              expect(life_cycle_event.location_id).to eq location.id
              result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                                input: {
                                                  locationId: location_id,
                                                  force: true
                                                }
                                              })
              expect(result).to_not include 'errors'
              expect(result).to include 'data'
              expect(result['data']['softDeleteLocation']).to include 'location'
              expect(result['data']['softDeleteLocation']['location']['id']).to eq location_id
              expect(result['data']['softDeleteLocation']['location']['visibility']).to eq "DELETED"
              expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
              location.reload
              expect(location.visibility).to eq 'deleted'
            end
          end
        end
        context 'and the life_cycle_event is soft-deleted' do
          let(:life_cycle_event) { create(:planting_event, location: location, deleted: true) }
          it 'soft deletes the record' do
            location_id = PlantApiSchema.id_from_object(location, Location, {})
            record_id = location.id
            expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            expect(life_cycle_event.location_id).to eq location.id
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                locationId: location_id
                                              }
                                            })
            expect(result).to_not include 'errors'
            expect(result).to include 'data'
            expect(result['data']['softDeleteLocation']).to include 'location'
            expect(result['data']['softDeleteLocation']['location']['id']).to eq location_id
            expect(result['data']['softDeleteLocation']['location']['visibility']).to eq "DELETED"
            expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            location.reload
            expect(location.visibility).to eq 'deleted'
          end
        end
        context 'with multiple relationships with different visibility values' do
          let(:deleted_life_cycle_event_a) { create(:planting_event, location: location, deleted: true) }
          let(:deleted_life_cycle_event_b) { create(:movement_event, location: location, deleted: true) }
          let(:life_cycle_event_c) { create(:planting_event, location: location) }
          let(:life_cycle_event_d) { create(:movement_event, location: location) }

          it 'returns multiple errors' do
            # refer to life_cycle_events so they are created
            deleted_life_cycle_event_a
            deleted_life_cycle_event_b
            life_cycle_event_c
            life_cycle_event_d

            location_id = PlantApiSchema.id_from_object(location, Location, {})
            record_id = location.id
            expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
            result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                              input: {
                                                locationId: location_id
                                              }
                                            })
            expect(result['data']['softDeleteLocation']).to include 'location'
            expect(result['data']['softDeleteLocation']['location']['visibility']).to_not eq "DELETED"
            expect(result['data']['softDeleteLocation']['errors'][0]).to include 'code'
            expect(result['data']['softDeleteLocation']['errors'][0]['code']).to eq 400
            expect(result['data']['softDeleteLocation']['errors'][1]).to include 'code'
            expect(result['data']['softDeleteLocation']['errors'][1]['code']).to eq 400
            expect { Location.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end
end
