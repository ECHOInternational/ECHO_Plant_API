# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Life Cycle Event Query', type: :graphql_query do
  context 'Nutrient Deficiency' do
    it 'loads a nutrient deficiency life cycle event by ID' do
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
      nutrient_deficiency_event = create(:nutrient_deficiency_event, notes: 'loaded by id', specimen: specimen)
      nutrient_deficiency_event_id = PlantApiSchema.id_from_object(nutrient_deficiency_event, NutrientDeficiencyEvent, {})
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user }, variables: { id: nutrient_deficiency_event_id })
      life_cycle_event_result = result['data']['lifeCycleEvent']
      # Make sure the query worked
      expect(life_cycle_event_result['id']).to eq nutrient_deficiency_event_id
      expect(life_cycle_event_result['notes']).to eq 'loaded by id'
      expect(life_cycle_event_result['__typename']).to eq 'NutrientDeficiencyEvent'
    end
  end
end
