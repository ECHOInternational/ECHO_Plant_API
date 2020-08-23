# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Planting Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:location) { create(:location, owned_by: current_user.email) }
  let(:life_cycle_event) { create(:planting_event, specimen: specimen) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdatePlantingLifeCycleEventInput!){
			updatePlantingEvent(input: $input){
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
          location{
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
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, PlantingEvent, {})
      @location_id = PlantApiSchema.id_from_object(location, Location, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           datetime: '2014-07-16T19:23:00Z',
                                           notes: 'newly updated record',
                                           locationId: @location_id,
                                           quantity: 523.0,
                                           unit: 'WEIGHT',
                                           betweenRowSpacing: 9,
                                           inRowSpacing: 4,
                                           lifeCycleEventId: @life_cycle_event_id
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'updates a record' do
      success_result = @result['data']['updatePlantingEvent']['plantingEvent']
      expect(success_result['notes']).to eq 'newly updated record'
      expect(success_result['id']).to eq @life_cycle_event_id

      updated_event = LifeCycleEvent.find success_result['uuid']
      expect(updated_event).to_not be nil
      expect(updated_event.notes).to eq 'newly updated record'
    end
  end
  describe 'required parameters' do
    it 'returns errors when the location is not found' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, PlantingEvent, {})
      fake_location_id = GraphQL::Schema::UniqueWithinType.encode(Location.name, SecureRandom.uuid)
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          quantity: 523.0,
                                          unit: 'WEIGHT',
                                          betweenRowSpacing: 9,
                                          inRowSpacing: 4,
                                          lifeCycleEventId: @life_cycle_event_id,
                                          locationId: fake_location_id
                                        }
                                      })
      expect(result['errors'].count).to be_positive
      expect(result['data']).to be_nil
    end
  end
end
