# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Flowering' do
    it 'loads a flowering life cycle event by ID' do
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
          ... on FloweringEvent {
            percent
          }
        }
      }
      GRAPHQL

      current_user = build(:user, :readwrite)
      specimen = create(:specimen, owned_by: current_user.email)
      flowering_event = create(:flowering_event, notes: 'loaded by id', specimen: specimen)
      flowering_event_id = PlantApiSchema.id_from_object(flowering_event, FloweringEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: flowering_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq flowering_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'FloweringEvent'
      expect(life_cycle_event_result['percent']).to_not be_nil
    end
  end
end
