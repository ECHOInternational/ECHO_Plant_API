# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Harvest' do
    it 'loads a harvest life cycle event by ID' do
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
          ... on HarvestEvent {
            quantity
            unit
            quality
          }
        }
      }
      GRAPHQL

      current_user = build(:user, :readwrite)
      specimen = create(:specimen, owned_by: current_user.email)
      harvest_event = create(:harvest_event, notes: 'loaded by id', specimen: specimen)
      harvest_event_id = PlantApiSchema.id_from_object(harvest_event, HarvestEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: harvest_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq harvest_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'HarvestEvent'
      expect(life_cycle_event_result['quantity']).to_not be_nil
      expect(life_cycle_event_result['unit']).to_not be_nil
      expect(life_cycle_event_result['quality']).to_not be_nil
    end
  end
end
