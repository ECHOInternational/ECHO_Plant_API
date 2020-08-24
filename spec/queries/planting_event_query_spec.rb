# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Planting' do
    it 'loads a planting life cycle event by ID' do
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
          ... on PlantingEvent {
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

      current_user = build(:user, :readwrite)
      specimen = create(:specimen, owned_by: current_user.email)
      planting_event = create(:planting_event, notes: 'loaded by id', specimen: specimen)
      planting_event_id = PlantApiSchema.id_from_object(planting_event, PlantingEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: planting_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq planting_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'PlantingEvent'
      expect(life_cycle_event_result['location']).to_not be_nil
      expect(life_cycle_event_result['quantity']).to_not be_nil
      expect(life_cycle_event_result['unit']).to_not be_nil
      expect(life_cycle_event_result['betweenRowSpacing']).to_not be_nil
      expect(life_cycle_event_result['inRowSpacing']).to_not be_nil
    end
  end
end
