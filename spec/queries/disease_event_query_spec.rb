# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Disease' do
    it 'loads a disease life cycle event by ID' do
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
      disease_event = create(:disease_event, notes: 'loaded by id', specimen: specimen)
      disease_event_id = PlantApiSchema.id_from_object(disease_event, DiseaseEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: disease_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq disease_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'DiseaseEvent'
    end
  end
end
