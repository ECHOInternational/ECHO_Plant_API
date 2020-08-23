# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Pest' do
    it 'loads a pest life cycle event by ID' do
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
      pest_event = create(:pest_event, notes: 'loaded by id', specimen: specimen)
      pest_event_id = PlantApiSchema.id_from_object(pest_event, PestEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: pest_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq pest_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'PestEvent'
    end
  end
end
