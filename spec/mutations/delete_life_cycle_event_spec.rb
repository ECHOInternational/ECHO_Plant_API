# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Delete Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { nil }
  let(:life_cycle_event) { create(:acquire_event) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: DeleteLifeCycleEventInput!){
			deleteLifeCycleEvent(input: $input){
				lifeCycleEventId
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
      life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, life_cycle_event.class, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          lifeCycleEventId: life_cycle_event_id
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
      life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, life_cycle_event.class, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                        input: {
                                          lifeCycleEventId: life_cycle_event_id
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
    let(:specimen) { build(:specimen, owned_by: current_user.email) }
    let(:life_cycle_event) { create(:acquire_event, notes: 'some_notes', specimen: specimen) }

    context 'when the user does not own the record' do
      let(:specimen) { build(:specimen, owned_by: 'notme') }
      it 'raises an error' do
        @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, life_cycle_event.class, {})
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            lifeCycleEventId: @life_cycle_event_id
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
        @life_cycle_event_id = PlantApiSchema.id_from_object(life_cycle_event, life_cycle_event.class, {})
      end
      it 'deletes the record' do
        record_id = life_cycle_event.id
        record = LifeCycleEvent.find record_id
        expect(record).to_not be_nil
        expect(record.deleted).to be false
        # expect { LifeCycleEvent.find record_id }.to_not raise_error(ActiveRecord::RecordNotFound)
        result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                          input: {
                                            lifeCycleEventId: @life_cycle_event_id
                                          }
                                        })
        expect(result).to_not include 'errors'
        expect(result).to include 'data'
        expect(result['data']['deleteLifeCycleEvent']).to include 'lifeCycleEventId'
        expect(result['data']['deleteLifeCycleEvent']['lifeCycleEventId']).to eq @life_cycle_event_id
        record.reload
        expect(record.deleted).to be true
      end
    end
  end
end
