# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Antinutrient Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads antinutrients by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			antinutrient(id: $id){
				id
				name
			}
		}
    GRAPHQL

    antinutrient = create(:antinutrient, name: 'loaded by id')
    antinutrient_id = PlantApiSchema.id_from_object(antinutrient, Antinutrient, {})
    result = PlantApiSchema.execute(query_string, variables: { id: antinutrient_id })
    antinutrient_result = result['data']['antinutrient']
    # Make sure the query worked
    expect(antinutrient_result['id']).to eq antinutrient_id
    expect(antinutrient_result['name']).to eq 'loaded by id'
  end

  it 'falls back to a language when the one requested is not available' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			antinutrient(id: $id, language: $language){
				id
				name
			}
		}
    GRAPHQL

    antinutrient = create(:antinutrient, name: 'name in english')
    antinutrient.name_es = 'name in spanish'
    antinutrient.save

    antinutrient_id = PlantApiSchema.id_from_object(antinutrient, Antinutrient, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: antinutrient_id, language: 'en' })
    result_fr = PlantApiSchema.execute(query_string, variables: { id: antinutrient_id, language: 'fr' })

    antinutrient_result_en = result_en['data']['antinutrient']
    antinutrient_result_fr = result_fr['data']['antinutrient']
    # Make sure the query worked
    expect(antinutrient_result_en['id']).to eq antinutrient_id
    expect(antinutrient_result_en['name']).to eq 'name in english'
    expect(antinutrient_result_fr['id']).to eq antinutrient_id
    expect(antinutrient_result_fr['name']).to eq 'name in english'
  end

  describe 'translations attribute' do
    it 'returns a list of languages when requested' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				antinutrient(id: $id){
					id
					name
					translations{
						locale
						name
					}
				}
			}
      GRAPHQL

      antinutrient = create(:antinutrient, name: 'nameen')
      antinutrient.name_es = 'namees'
      antinutrient.save

      antinutrient_id = PlantApiSchema.id_from_object(antinutrient, Antinutrient, {})
      result = PlantApiSchema.execute(query_string, variables: { id: antinutrient_id })

      antinutrient_result = result['data']['antinutrient']

      expect(antinutrient_result['id']).to eq antinutrient_id
      expect(antinutrient_result['translations']).to be_kind_of Array
      expect(antinutrient_result['translations'].length).to eq 2

      result_en = antinutrient_result['translations'].detect { |l| l['locale'] == 'en' }
      result_es = antinutrient_result['translations'].detect { |l| l['locale'] == 'es' }

      expect(result_en['name']).to eq 'nameen'
      expect(result_es['name']).to eq 'namees'
    end
  end
end
