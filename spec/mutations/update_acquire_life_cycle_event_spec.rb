# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Update Acquire Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:life_cycle_event) { create(:acquire_event, specimen: specimen) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: UpdateAcquireLifeCycleEventInput!){
			updateAcquireEvent(input: $input){
        errors{
          field
          value
          message
          code
        }
				acquireEvent{
          id
          uuid
          datetime
          notes
          specimen{
            id
          }
          condition
          accession
          source
        }
			}
		}
    GRAPHQL
  }

  context 'with valid parameters' do
    before :each do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, AcquireEvent, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           datetime: '2014-07-16T19:23:00Z',
                                           notes: 'newly updated record',
                                           condition: 'GOOD',
                                           accession: 'Accession 1',
                                           source: 'Source',
                                           lifeCycleEventId: @life_cycle_event_id
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'updates a record' do
      success_result = @result['data']['updateAcquireEvent']['acquireEvent']
      expect(success_result['notes']).to eq 'newly updated record'
      expect(success_result['id']).to eq @life_cycle_event_id

      updated_event = LifeCycleEvent.find success_result['uuid']
      expect(updated_event).to_not be nil
      expect(updated_event.notes).to eq 'newly updated record'
    end
  end
  describe 'required parameters' do
    it 'returns errors when the condition is blank' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, AcquireEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          accession: 'Accession 1',
                                          source: 'Source',
                                          lifeCycleEventId: @life_cycle_event_id,
                                          condition: ''
                                        }
                                      })
      error_result = result['data']['updateAcquireEvent']['errors']
      expect(error_result[0]['field']).to eq 'condition'
      expect(error_result[0]['code']).to eq 400
    end
    it 'returns errors when the source is blank' do
      @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, AcquireEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          datetime: '2014-07-16T19:23:00Z',
                                          notes: 'newly updated record',
                                          condition: 'GOOD',
                                          accession: 'Accession 1',
                                          lifeCycleEventId: @life_cycle_event_id,
                                          source: ''
                                        }
                                      })
      error_result = result['data']['updateAcquireEvent']['errors']
      expect(error_result[0]['field']).to eq 'source'
      expect(error_result[0]['code']).to eq 400
    end
  end
end
