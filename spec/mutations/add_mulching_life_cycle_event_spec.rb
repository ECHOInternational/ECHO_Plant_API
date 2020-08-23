# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Add Mulching Life Cycle Event Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:specimen) { create(:specimen, owned_by: current_user.email) }
  let(:query_string) {
    <<-GRAPHQL
		mutation($input: AddMulchingLifeCycleEventInput!){
			addMulchingEventToSpecimen(input: $input){
        errors{
          field
          value
          message
          code
        }
				mulchingEvent{
          id
          uuid
          datetime
          notes
          specimen{
            id
          }
        }
			}
		}
    GRAPHQL
  }

  context 'with valid parameters' do
    before :each do
      @specimen_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      @result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: {
                                         input: {
                                           datetime: '2013-07-16T19:23:00Z',
                                           notes: 'newly created record',
                                           specimenId: @specimen_id
                                         }
                                       })
    end
    it 'completes successfully' do
      expect(@result).to_not include 'errors'
      expect(@result).to include 'data'
    end

    it 'creates a record' do
      success_result = @result['data']['addMulchingEventToSpecimen']['mulchingEvent']
      expect(success_result['notes']).to eq 'newly created record'
      expect(success_result['specimen']['id']).to eq @specimen_id

      created_event = LifeCycleEvent.find success_result['uuid']
      expect(created_event).to_not be nil
      expect(created_event.notes).to eq 'newly created record'
    end
  end
  describe 'required parameters' do
  end
end
