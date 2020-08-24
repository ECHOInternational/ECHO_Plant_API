# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Harvest Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:life_cycle_event) { create(:harvest_event, specimen: specimen) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdateHarvestLifeCycleEventInput!){
			updateHarvestEvent(input: $input){
        errors{
          field
          value
          message
          code
        }
				harvestEvent{
          id
          uuid
          datetime
          notes
          specimen{
            id
          }
          quantity
          unit
          quality
        }
			}
		}
    GRAPHQL
  }

  context 'with valid parameters' do
    before :each do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, HarvestEvent, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           datetime: '2014-07-16T19:23:00Z',
                                           notes: 'newly updated record',
                                           quantity: 517.0,
                                           unit: 'WEIGHT',
                                           quality: 4,
                                           lifeCycleEventId: @life_cycle_event_id
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'updates a record' do
      success_result = @result['data']['updateHarvestEvent']['harvestEvent']
      expect(success_result['notes']).to eq 'newly updated record'
      expect(success_result['id']).to eq @life_cycle_event_id

      updated_event = LifeCycleEvent.find success_result['uuid']
      expect(updated_event).to_not be nil
      expect(updated_event.notes).to eq 'newly updated record'
    end
  end
  describe 'required parameters' do
    it 'returns errors when the quantity is blank' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, HarvestEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          unit: 'WEIGHT',
                                          quality: 4,
                                          lifeCycleEventId: @life_cycle_event_id,
                                          quantity: ''
                                        }
                                      })
      expect(result).to include 'errors'
      expect(result).to_not include 'data'
    end
    it 'returns errors when the unit is blank' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, HarvestEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          quantity: 517.0,
                                          quality: 4,
                                          lifeCycleEventId: @life_cycle_event_id,
                                          unit: ''
                                        }
                                      })
      expect(result).to include 'errors'
      expect(result).to_not include 'data'
    end
    it 'returns errors when the quality is blank' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, HarvestEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          quantity: 517.0,
                                          unit: 'WEIGHT',
                                          lifeCycleEventId: @life_cycle_event_id,
                                          quality: ''
                                        }
                                      })
      expect(result).to include 'errors'
      expect(result).to_not include 'data'
    end
  end
end
