# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tolerance Query', type: :graphql_query do
  before :each do
    Mobility.locale = nil
  end

  it 'loads tolerances by ID' do
    query_string = <<-GRAPHQL
		query($id: ID!){
			tolerance(id: $id){
				id
				name
			}
		}
    GRAPHQL

    tolerance = create(:tolerance, name: 'loaded by id')
    tolerance_id = PlantApiSchema.id_from_object(tolerance, Tolerance, {})
    result = PlantApiSchema.execute(query_string, variables: { id: tolerance_id })
    tolerance_result = result['data']['tolerance']
    # Make sure the query worked
    expect(tolerance_result['id']).to eq tolerance_id
    expect(tolerance_result['name']).to eq 'loaded by id'
  end

  it 'falls back to a language when the one requested is not available' do
    query_string = <<-GRAPHQL
		query($id: ID!, $language: String){
			tolerance(id: $id, language: $language){
				id
				name
			}
		}
    GRAPHQL

    tolerance = create(:tolerance, name: 'name in english')
    tolerance.name_es = 'name in spanish'
    tolerance.save

    tolerance_id = PlantApiSchema.id_from_object(tolerance, Tolerance, {})
    result_en = PlantApiSchema.execute(query_string, variables: { id: tolerance_id, language: 'en' })
    result_fr = PlantApiSchema.execute(query_string, variables: { id: tolerance_id, language: 'fr' })

    tolerance_result_en = result_en['data']['tolerance']
    tolerance_result_fr = result_fr['data']['tolerance']
    # Make sure the query worked
    expect(tolerance_result_en['id']).to eq tolerance_id
    expect(tolerance_result_en['name']).to eq 'name in english'
    expect(tolerance_result_fr['id']).to eq tolerance_id
    expect(tolerance_result_fr['name']).to eq 'name in english'
  end

  describe 'translations attribute' do
    it 'returns a list of languages when requested' do
      query_string = <<-GRAPHQL
			query($id: ID!){
				tolerance(id: $id){
					id
					name
					translations{
						locale
						name
					}
				}
			}
      GRAPHQL

      tolerance = create(:tolerance, name: 'nameen')
      tolerance.name_es = 'namees'
      tolerance.save

      tolerance_id = PlantApiSchema.id_from_object(tolerance, Tolerance, {})
      result = PlantApiSchema.execute(query_string, variables: { id: tolerance_id })

      tolerance_result = result['data']['tolerance']

      expect(tolerance_result['id']).to eq tolerance_id
      expect(tolerance_result['translations']).to be_kind_of Array
      expect(tolerance_result['translations'].length).to eq 2

      result_en = tolerance_result['translations'].detect { |l| l['locale'] == 'en' }
      result_es = tolerance_result['translations'].detect { |l| l['locale'] == 'es' }

      expect(result_en['name']).to eq 'nameen'
      expect(result_es['name']).to eq 'namees'
    end
  end
end
