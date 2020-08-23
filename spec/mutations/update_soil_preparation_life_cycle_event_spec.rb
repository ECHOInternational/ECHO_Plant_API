# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Soil Preparation Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:life_cycle_event) { create(:soil_preparation_event, specimen: specimen) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdateSoilPreparationLifeCycleEventInput!){
			updateSoilPreparationEvent(input: $input){
        errors{
          field
          value
          message
          code
        }
				soilPreparationEvent{
          id
          uuid
          datetime
          notes
          specimen{
            id
          }
          soilPreparation
        }
			}
		}
    GRAPHQL
  }

  context 'with valid parameters' do
    before :each do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, SoilPreparationEvent, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           datetime: '2014-07-16T19:23:00Z',
                                           notes: 'newly updated record',
                                           soilPreparation: 'FULL_TILL',
                                           lifeCycleEventId: @life_cycle_event_id
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'updates a record' do
      success_result = @result['data']['updateSoilPreparationEvent']['soilPreparationEvent']
      expect(success_result['notes']).to eq 'newly updated record'
      expect(success_result['id']).to eq @life_cycle_event_id

      updated_event = LifeCycleEvent.find success_result['uuid']
      expect(updated_event).to_not be nil
      expect(updated_event.notes).to eq 'newly updated record'
    end
  end
  describe 'required parameters' do
    it 'returns errors when the soil_preparation is blank' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, SoilPreparationEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          lifeCycleEventId: @life_cycle_event_id,
                                          soilPreparation: ''
                                        }
                                      })
      expect(result).to include 'errors'
      expect(result).to_not include 'data'
    end
  end
end
