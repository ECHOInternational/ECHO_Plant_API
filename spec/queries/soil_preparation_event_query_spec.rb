# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Soil Preparation' do
    it 'loads a soil preparation life cycle event by ID' do
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
          ... on SoilPreparationEvent {
            soilPreparation
          }
        }
      }
      GRAPHQL

      current_user = build(:user, :readwrite)
      specimen = create(:specimen, owned_by: current_user.email)
      soil_preparation_event = create(:soil_preparation_event, notes: 'loaded by id', specimen: specimen)
      soil_preparation_event_id = PlantApiSchema.id_from_object(soil_preparation_event, SoilPreparationEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: soil_preparation_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq soil_preparation_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'SoilPreparationEvent'
      expect(life_cycle_event_result['soilPreparation']).to_not be_nil
    end
  end
end
