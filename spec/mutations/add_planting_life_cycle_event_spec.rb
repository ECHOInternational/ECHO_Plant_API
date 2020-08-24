# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Add Planting Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:location) { create(:location, owned_by: current_user.email) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: AddPlantingLifeCycleEventInput!){
			addPlantingEventToSpecimen(input: $input){
        errors{
          field
          value
          message
          code
        }
				plantingEvent{
          id
          uuid
          datetime
          notes
          specimen{
            id
          }
          location {
            id
          }
          quantity
          unit
          betweenRowSpacing
          inRowSpacing
        }
			}
		}
    GRAPHQL
  }

  context 'with valid parameters' do
    before :each do
      @specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      @location_id = PlantApiSchema.id_from_object(location, Location, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           datetime: '2013-07-16T19:23:00Z',
                                           notes: 'newly created record',
                                           locationId: @location_id,
                                           quantity: 598.0,
                                           unit: 'WEIGHT',
                                           betweenRowSpacing: 62,
                                           inRowSpacing: 24,
                                           specimenId: @specimen_id
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'creates a record' do
      success_result = @result['data']['addPlantingEventToSpecimen']['plantingEvent']
      expect(success_result['notes']).to eq 'newly created record'
      expect(success_result['specimen']['id']).to eq @specimen_id
      expect(success_result['location']['id']).to eq @location_id

      created_event = LifeCycleEvent.find success_result['uuid']
      expect(created_event).to_not be nil
      expect(created_event.notes).to eq 'newly created record'
    end
  end
  describe 'required parameters' do
    it 'returns errors when the location doesnt exist' do
      @specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      fake_location_id = GraphQL::Schema::UniqueWithinType.encode(Location.name, SecureRandom.uuid)
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2013-07-16T19:23:00Z',
                                          notes: 'newly created record',
                                          quantity: 598.0,
                                          unit: 'WEIGHT',
                                          betweenRowSpacing: 62,
                                          inRowSpacing: 24,
                                          specimenId: @specimen_id,
                                          location: fake_location_id
                                        }
                                      })
      expect(result['errors'].count).to be_positive
      expect(result['data']).to be_nil
    end
  end
end
