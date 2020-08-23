# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Staking' do
    it 'loads a staking life cycle event by ID' do
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
        }
      }
      GRAPHQL

      current_user = build(:user, :readwrite)
      specimen = create(:specimen, owned_by: current_user.email)
      staking_event = create(:staking_event, notes: 'loaded by id', specimen: specimen)
      staking_event_id = PlantApiSchema.id_from_object(staking_event, StakingEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: staking_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq staking_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'StakingEvent'
    end
  end
end
