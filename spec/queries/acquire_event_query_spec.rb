# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Acquire' do
    it 'loads a acquire life cycle event by ID' do
      query_string = <<-GRAPHQL
      query($id: ID!){
        lifeCycleEvent(id: $id){
          __typename
          id
          datetime
          notes
          specimen{
            id
          }
          ... on AcquireEvent {
            condition
            accession
            source
          }
        }
      }
      GRAPHQL

      current_user = build(:user, :readwrite)
      specimen = create(:specimen, owned_by: current_user.email)
      acquire_event = create(:acquire_event, notes: 'loaded by id', specimen: specimen)
      acquire_event_id = PlantApiSchema.id_from_object(acquire_event, AcquireEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: acquire_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq acquire_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'AcquireEvent'
      expect(life_cycle_event_result['condition']).to_not be_nil
      expect(life_cycle_event_result['accession']).to_not be_nil
      expect(life_cycle_event_result['source']).to_not be_nil
    end
  end
end
