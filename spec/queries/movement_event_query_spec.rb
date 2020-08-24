# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Movement' do
    it 'loads a movement life cycle event by ID' do
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
          ... on MovementEvent {
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
      movement_event = create(:movement_event, notes: 'loaded by id', specimen: specimen)
      movement_event_id = PlantApiSchema.id_from_object(movement_event, MovementEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: movement_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq movement_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'MovementEvent'
      expect(life_cycle_event_result['location']).to_not be_nil
      expect(life_cycle_event_result['quantity']).to_not be_nil
      expect(life_cycle_event_result['unit']).to_not be_nil
      expect(life_cycle_event_result['betweenRowSpacing']).to_not be_nil
      expect(life_cycle_event_result['inRowSpacing']).to_not be_nil
    end
  end
end
